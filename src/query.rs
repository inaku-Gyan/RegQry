use crate::{
    registry::{self, Root, Source, View},
    value::{Decoded, Environment, RawValue},
};

#[cfg(test)]
mod tests;
use jiff::Timestamp;
use regex::Regex;
use std::{
    cmp::Ordering,
    ffi::{OsStr, OsString},
    io,
    sync::atomic::{AtomicBool, Ordering as AtomicOrdering},
};

pub(crate) enum KeyPattern {
    Regex(Regex),
    Glob(Vec<Option<Regex>>),
}
impl KeyPattern {
    fn matches(&self, path: &str) -> bool {
        match self {
            Self::Regex(regex) => regex.is_match(path),
            Self::Glob(pattern) => {
                let closure = |states: &mut [bool]| {
                    for i in 0..pattern.len() {
                        if states[i] && pattern[i].is_none() {
                            states[i + 1] = true;
                        }
                    }
                };
                let mut states = vec![false; pattern.len() + 1];
                states[0] = true;
                closure(&mut states);
                for part in path.split('\\') {
                    let mut next = vec![false; states.len()];
                    for (i, atom) in pattern.iter().enumerate() {
                        if states[i] {
                            match atom {
                                None => next[i] = true,
                                Some(regex) if regex.is_match(part) => next[i + 1] = true,
                                _ => {}
                            }
                        }
                    }
                    closure(&mut next);
                    states = next;
                }
                states[pattern.len()]
            }
        }
    }
}
pub(crate) enum DataPattern {
    Text(Regex),
    Expanded(Regex),
    Hex(Vec<u8>),
    Empty,
    Zero,
}
pub(crate) struct Plan {
    pub(crate) roots: Vec<Root>,
    pub(crate) views: Vec<View>,
    pub(crate) keys: Vec<KeyPattern>,
    pub(crate) names: Vec<Regex>,
    pub(crate) data: Vec<DataPattern>,
    pub(crate) types: Vec<u32>,
    pub(crate) not_types: Vec<u32>,
    pub(crate) not_set: bool,
    pub(crate) after: Vec<Timestamp>,
    pub(crate) before: Vec<Timestamp>,
}
impl Plan {
    fn values(&self) -> bool {
        !self.names.is_empty()
            || !self.types.is_empty()
            || !self.not_types.is_empty()
            || !self.data.is_empty()
            || self.not_set
    }
    fn key_matches(&self, path: &OsStr, modified: u64) -> io::Result<bool> {
        let nanos = (i128::from(modified) - 116_444_736_000_000_000) * 100;
        if !self.after.iter().all(|t| nanos > t.as_nanosecond())
            || !self.before.iter().all(|t| nanos < t.as_nanosecond())
        {
            return Ok(false);
        }
        if self.keys.is_empty() {
            return Ok(true);
        }
        let path = path
            .to_str()
            .ok_or_else(|| io::Error::other("key pattern requires valid UTF-16"))?;
        Ok(self.keys.iter().any(|pattern| pattern.matches(path)))
    }
    fn name_matches(&self, name: &OsStr) -> io::Result<bool> {
        if self.names.is_empty() {
            return Ok(true);
        }
        let name = name
            .to_str()
            .ok_or_else(|| io::Error::other("name pattern requires valid UTF-16"))?;
        Ok(self.names.iter().any(|pattern| pattern.is_match(name)))
    }
    fn value_matches(&self, value: &RawValue, env: &Environment) -> io::Result<bool> {
        if (!self.types.is_empty() && !self.types.contains(&value.kind))
            || self.not_types.contains(&value.kind)
        {
            return Ok(false);
        }
        let name = self.name_matches(&value.name);
        if matches!(name, Ok(false)) {
            return Ok(false);
        }
        let data = self.data_matches(value, env);
        match (name, data) {
            (_, Ok(false)) => Ok(false),
            (Err(error), _) | (_, Err(error)) => Err(error),
            (Ok(true), Ok(true)) => Ok(true),
            (Ok(false), _) => unreachable!(),
        }
    }
    fn data_matches(&self, value: &RawValue, env: &Environment) -> io::Result<bool> {
        if self.data.is_empty() {
            return Ok(!self.not_set);
        }
        let mut failure = None;
        for condition in &self.data {
            let outcome = match condition {
                DataPattern::Zero => Ok(value.bytes.is_empty()),
                DataPattern::Hex(needle) => {
                    Ok(memchr::memmem::find(&value.bytes, needle).is_some())
                }
                DataPattern::Empty => value.empty().map_err(str::to_owned),
                DataPattern::Text(regex) => value.text_matches(regex).map_err(str::to_owned),
                DataPattern::Expanded(regex) if value.kind == 2 => match value.decoded() {
                    Ok(Decoded::Text(text)) => {
                        env.expand(text).map(|expanded| regex.is_match(&expanded))
                    }
                    Err(e) => Err(e.to_owned()),
                    _ => unreachable!(),
                },
                DataPattern::Expanded(_) => Ok(false),
            };
            match outcome {
                Ok(true) => return Ok(true),
                Ok(false) => {}
                Err(error) => failure = Some(error),
            }
        }
        match failure {
            Some(error) => Err(io::Error::other(error)),
            None => Ok(false),
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct Target {
    pub(crate) view: View,
    pub(crate) key: OsString,
    pub(crate) name: Option<OsString>,
}
impl Target {
    fn compare(&self, other: &Self) -> io::Result<Ordering> {
        let order = self.view.cmp(&other.view);
        if order != Ordering::Equal {
            return Ok(order);
        }
        let order = registry::ordinal_path(&self.key, &other.key)?;
        if order != Ordering::Equal {
            return Ok(order);
        }
        match (&self.name, &other.name) {
            (None, None) => Ok(Ordering::Equal),
            (None, Some(_)) => Ok(Ordering::Less),
            (Some(_), None) => Ok(Ordering::Greater),
            (Some(a), Some(b)) => registry::ordinal(a, b),
        }
    }
}
// Fallible ordinal comparisons keep OS failures observable. Binary lookup avoids
// comparing every preceding result; the vector contains only emitted identities.
#[derive(Default)]
struct Seen(Vec<Target>);
impl Seen {
    fn insert(&mut self, target: &Target) -> io::Result<bool> {
        let (mut low, mut high) = (0, self.0.len());
        while low < high {
            let mid = low + (high - low) / 2;
            match self.0[mid].compare(target)? {
                Ordering::Equal => return Ok(false),
                Ordering::Less => low = mid + 1,
                Ordering::Greater => high = mid,
            }
        }
        self.0.try_reserve(1).map_err(io::Error::other)?;
        self.0.insert(low, target.clone());
        Ok(true)
    }
}
pub(crate) trait Sink {
    fn key(&mut self, target: &Target) -> io::Result<()>;
    fn value(&mut self, target: &Target, value: Option<&RawValue>) -> io::Result<()>;
    fn diagnostic(&mut self, target: &Target, operation: &str, error: &io::Error)
    -> io::Result<()>;
    fn finish(&mut self, summary: &Summary) -> io::Result<()>;
}
#[derive(Default, Debug)]
pub(crate) struct Summary {
    pub(crate) matched: bool,
    pub(crate) incomplete: bool,
    pub(crate) cancelled: bool,
    pub(crate) output_failed: bool,
    pub(crate) errors: usize,
}
impl Summary {
    pub(crate) fn code(&self) -> u8 {
        if self.output_failed {
            2
        } else if self.cancelled {
            130
        } else if self.incomplete {
            2
        } else if self.matched {
            0
        } else {
            1
        }
    }
}
struct Run<'a, S: Sink> {
    sink: &'a mut S,
    seen: Seen,
    summary: Summary,
    cancelled: &'a AtomicBool,
}
impl<S: Sink> Run<'_, S> {
    fn error(&mut self, target: &Target, operation: &str, error: io::Error) {
        if self.cancelled.load(AtomicOrdering::Relaxed) {
            return;
        }
        self.summary.incomplete = true;
        self.summary.errors = self.summary.errors.saturating_add(1);
        if self.sink.diagnostic(target, operation, &error).is_err() {
            self.summary.output_failed = true;
        }
    }
    fn stopped(&self) -> bool {
        self.summary.output_failed || self.cancelled.load(AtomicOrdering::Relaxed)
    }
    fn emit(&mut self, target: &Target, value: Option<&RawValue>) {
        match self.seen.insert(target) {
            Ok(false) => {}
            Ok(true) => {
                let outcome = if target.name.is_some() {
                    self.sink.value(target, value)
                } else {
                    self.sink.key(target)
                };
                if let Err(error) = outcome {
                    self.summary.output_failed = true;
                    self.summary.incomplete = true;
                    self.summary.errors = self.summary.errors.saturating_add(1);
                    let _ = self.sink.diagnostic(target, "write result", &error);
                } else {
                    self.summary.matched = true;
                }
            }
            Err(e) => self.error(target, "deduplicate identity", e),
        }
    }
    fn values<R: Source>(
        &mut self,
        plan: &Plan,
        env: &Environment,
        source: &R,
        parent: &R::Key,
        child: &OsStr,
        target: &Target,
    ) {
        let key = match source.open_child(parent, child, target.view, true) {
            Ok(key) => key,
            Err(e) => {
                self.error(target, "open values", e);
                return;
            }
        };
        // A not-set-only data group cannot match actual values.
        if !plan.not_set || !plan.data.is_empty() {
            let mut index = 0u32;
            loop {
                if self.stopped() {
                    return;
                }
                let name = match source.value_at(&key, index) {
                    Ok(Some(name)) => name,
                    Ok(None) => break,
                    Err(e) => {
                        self.error(target, "enumerate values", e);
                        break;
                    }
                };
                let value_target = Target {
                    view: target.view,
                    key: target.key.clone(),
                    name: Some(name.clone()),
                };
                if !matches!(plan.name_matches(&name), Ok(false)) {
                    match source.read(&key, &name) {
                        Ok(value) => match plan.value_matches(&value, env) {
                            Ok(true) => self.emit(&value_target, Some(&value)),
                            Ok(false) => {}
                            Err(e) => self.error(&value_target, "match value", e),
                        },
                        Err(e) => self.error(&value_target, "read value", e),
                    }
                }
                match index.checked_add(1) {
                    Some(next) => index = next,
                    None => {
                        self.error(
                            target,
                            "enumerate values",
                            io::Error::other("value index overflow"),
                        );
                        break;
                    }
                }
            }
        }
        if plan.not_set && plan.types.is_empty() && plan.not_types.is_empty() && !self.stopped() {
            match plan.name_matches(OsStr::new("")) {
                Ok(true) => {
                    let missing = Target {
                        view: target.view,
                        key: target.key.clone(),
                        name: Some(OsString::new()),
                    };
                    match source.read(&key, OsStr::new("")) {
                        Ok(_) => {}
                        Err(e) if registry::confirmed_value_missing(&e) => {
                            self.emit(&missing, None)
                        }
                        Err(e) => self.error(&missing, "confirm default value", e),
                    }
                }
                Ok(false) => {}
                Err(e) => self.error(target, "match default name", e),
            }
        }
    }
}
pub(crate) fn execute<R: Source, S: Sink>(
    plan: &Plan,
    env: &Environment,
    source: &R,
    sink: &mut S,
    cancelled: &AtomicBool,
) -> Summary {
    struct Frame<K> {
        key: K,
        index: u32,
        full: OsString,
        relative: OsString,
    }
    let mut run = Run {
        sink,
        seen: Seen::default(),
        summary: Summary::default(),
        cancelled,
    };
    'roots: for view in &plan.views {
        for root in &plan.roots {
            if run.stopped() {
                break 'roots;
            }
            let full = match root.full_path() {
                Ok(full) => full,
                Err(e) => {
                    run.error(
                        &Target {
                            view: *view,
                            key: root.hive.into(),
                            name: None,
                        },
                        "build root path",
                        e,
                    );
                    continue;
                }
            };
            let target = Target {
                view: *view,
                key: full.clone(),
                name: None,
            };
            let key = match source.open_root(root, *view) {
                Ok(key) => key,
                Err(e) => {
                    run.error(&target, "open root", e);
                    continue;
                }
            };
            let mut stack = vec![Frame {
                key,
                index: 0,
                full,
                relative: OsString::new(),
            }];
            while let Some(frame) = stack.last_mut() {
                if run.stopped() {
                    break 'roots;
                }
                let child = match source.child_at(&frame.key, frame.index) {
                    Ok(Some(child)) => child,
                    Ok(None) => {
                        stack.pop();
                        continue;
                    }
                    Err(e) => {
                        run.error(
                            &Target {
                                view: *view,
                                key: frame.full.clone(),
                                name: None,
                            },
                            "enumerate subkeys",
                            e,
                        );
                        stack.pop();
                        continue;
                    }
                };
                let next_index = frame.index.checked_add(1);
                if let Some(next) = next_index {
                    frame.index = next;
                }
                let paths = registry::join(&frame.full, &child.name).and_then(|full| {
                    registry::join(&frame.relative, &child.name).map(|relative| (full, relative))
                });
                let (full, relative) = match paths {
                    Ok(paths) => paths,
                    Err(e) => {
                        run.error(
                            &Target {
                                view: *view,
                                key: frame.full.clone(),
                                name: None,
                            },
                            "build child path",
                            e,
                        );
                        stack.pop();
                        continue;
                    }
                };
                let target = Target {
                    view: *view,
                    key: full.clone(),
                    name: None,
                };
                match plan.key_matches(&relative, child.modified) {
                    Ok(true) if plan.values() => {
                        run.values(plan, env, source, &frame.key, &child.name, &target)
                    }
                    Ok(true) => run.emit(&target, None),
                    Ok(false) => {}
                    Err(e) => run.error(&target, "match key", e),
                }
                if run.stopped() {
                    break 'roots;
                }
                let opened = source.open_child(&frame.key, &child.name, *view, false);
                if next_index.is_none() {
                    run.error(
                        &target,
                        "enumerate subkeys",
                        io::Error::other("subkey index overflow"),
                    );
                    stack.pop();
                }
                match opened {
                    Ok(key) => {
                        if let Err(e) = stack.try_reserve(1) {
                            run.error(&target, "grow traversal stack", io::Error::other(e));
                            continue;
                        }
                        stack.push(Frame {
                            key,
                            index: 0,
                            full,
                            relative,
                        });
                    }
                    Err(e) => run.error(&target, "open subkeys", e),
                }
            }
        }
    }
    run.summary.cancelled = cancelled.load(AtomicOrdering::Relaxed);
    if run.sink.finish(&run.summary).is_err() {
        run.summary.output_failed = true;
    }
    run.summary
}
