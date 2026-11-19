//! Test-only process control. The product has no fixture mode or environment override.
use super::{child, machine_path, text};
use crate::support::vm::{Context, assert_marker, wide};
use std::{
    ffi::OsString,
    fs::{self, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    os::windows::{
        ffi::OsStringExt,
        io::{AsRawHandle, FromRawHandle, OwnedHandle},
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    ptr,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};
use windows_sys::Win32::{
    Foundation::{WAIT_OBJECT_0, WAIT_TIMEOUT},
    System::{
        Console::{
            CTRL_C_EVENT, GenerateConsoleCtrlEvent, GetConsoleProcessList, SetConsoleCtrlHandler,
        },
        JobObjects::*,
        ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS},
        Registry::{KEY_QUERY_VALUE, KEY_WOW64_64KEY, REG_OPTION_OPEN_LINK},
        Threading::*,
    },
};
use winreg::RegKey;

const WIDTH: usize = 512;
const VALUES: usize = 8;
const WORKER: &str = "processes::isolated_console_probe";
const REQUEST: &str = "--skip=regqry-process-";

pub(super) fn prepare(root: &RegKey, context: &Context) {
    let bulk = child(root, "Bulk", KEY_WOW64_64KEY, context, 9);
    for index in 0..WIDTH {
        let node = child(
            &bulk,
            &format!("Node{index:04}"),
            KEY_WOW64_64KEY,
            context,
            9,
        );
        for value in 0..VALUES {
            text(
                &node,
                &format!("Payload{value}"),
                &format!("节点 {index:04}/{value} {}", "x".repeat(160)),
            );
        }
    }
    let long = child(root, "Long", KEY_WOW64_64KEY, context, 9);
    let leaf = child(&long, "Leaf", KEY_WOW64_64KEY, context, 9);
    text(
        &leaf,
        &"界".repeat(6000),
        &format!("{}END-OF-LARGE-VALUE", "x".repeat(512 * 1024)),
    );
    text(&leaf, "A\nB\t\u{1b}", "行一\n行二\t\u{1b}");
}

fn handle(raw: *mut std::ffi::c_void) -> OwnedHandle {
    assert!(!raw.is_null());
    // SAFETY: callers transfer one fresh, non-null owned Win32 handle.
    unsafe { OwnedHandle::from_raw_handle(raw) }
}
fn check(ok: i32) {
    assert_ne!(ok, 0, "{}", io::Error::last_os_error());
}

/// A new hidden console, never AttachConsole/FreeConsole on the caller. Closing
/// the noninherited job kills its whole tree, including after panic or timeout.
fn hidden_worker(directory: &Path, timeout: Duration) -> bool {
    let exe = std::env::current_exe().unwrap();
    let application = wide(exe.as_os_str());
    // Only the executable path needs quoting. Windows filenames cannot contain
    // quotes, and every other argument is fixed ASCII or hex; no shell is used.
    let mut command = OsString::from("\"");
    command.push(exe.as_os_str());
    command.push(format!(
        "\" --exact {WORKER} --nocapture --test-threads=1 {}",
        request_argument(directory)
    ));
    let mut command = wide(&command);
    // SAFETY: null security/name creates a fresh unnamed, noninheritable job.
    let job = handle(unsafe { CreateJobObjectW(ptr::null(), ptr::null()) });
    let mut limit = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
    limit.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    // SAFETY: the job is live and the correctly typed initialized structure has its exact size.
    check(unsafe {
        SetInformationJobObject(
            job.as_raw_handle(),
            JobObjectExtendedLimitInformation,
            (&limit as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
            std::mem::size_of_val(&limit) as u32,
        )
    });
    let startup = STARTUPINFOW {
        cb: std::mem::size_of::<STARTUPINFOW>() as u32,
        dwFlags: STARTF_USESHOWWINDOW,
        wShowWindow: 0, // SW_HIDE; no user32 dependency or visible helper window.
        ..Default::default()
    };
    let mut info = PROCESS_INFORMATION::default();
    // SAFETY: absolute application and writable NUL-terminated command buffers
    // stay live; initialized structures have their exact size. No handles are
    // inherited. Inheriting environment/CWD does not mutate either in the parent.
    check(unsafe {
        CreateProcessW(
            application.as_ptr(),
            command.as_mut_ptr(),
            ptr::null(),
            ptr::null(),
            0,
            CREATE_NEW_CONSOLE | CREATE_SUSPENDED,
            ptr::null(),
            ptr::null(),
            &startup,
            &mut info,
        )
    });
    let process = handle(info.hProcess);
    let primary_thread = handle(info.hThread);
    // Assign while suspended so the worker cannot spawn a child outside the job.
    // SAFETY: both live handles have the rights returned by their creation APIs.
    if unsafe { AssignProcessToJobObject(job.as_raw_handle(), process.as_raw_handle()) } == 0 {
        let error = io::Error::last_os_error();
        // SAFETY: this is only our still-suspended worker, not an unrelated process.
        unsafe {
            TerminateProcess(process.as_raw_handle(), 2);
        }
        panic!("cannot isolate worker in job: {error}");
    }
    // SAFETY: this is the newly created suspended primary thread.
    assert_ne!(
        unsafe { ResumeThread(primary_thread.as_raw_handle()) },
        u32::MAX
    );
    // SAFETY: process remains live for the wait; timeout is deliberately finite.
    let wait = unsafe {
        WaitForSingleObject(
            process.as_raw_handle(),
            timeout.as_millis().try_into().unwrap(),
        )
    };
    let timed_out = wait == WAIT_TIMEOUT;
    if timed_out {
        // SAFETY: terminate only this fresh job and its descendants on watchdog expiry.
        check(unsafe { TerminateJobObject(job.as_raw_handle(), 2) });
        // SAFETY: wait for our terminated worker to actually exit before removing its files.
        assert_eq!(
            unsafe { WaitForSingleObject(process.as_raw_handle(), 5000) },
            WAIT_OBJECT_0
        );
    } else {
        assert_eq!(wait, WAIT_OBJECT_0, "{}", io::Error::last_os_error());
        let mut code = 0;
        // SAFETY: the waited process handle and writable code are valid.
        check(unsafe { GetExitCodeProcess(process.as_raw_handle(), &mut code) });
        assert_eq!(
            code,
            0,
            "worker failed: {}",
            format_args!(
                "{}\n{}",
                fs::read_to_string(directory.join("result.txt")).unwrap_or_default(),
                fs::read_to_string(directory.join("progress.txt")).unwrap_or_default()
            )
        );
    }
    timed_out
}

fn request_argument(directory: &Path) -> String {
    let encoded = hex::encode(
        wide(directory.as_os_str())
            .iter()
            .flat_map(|n| n.to_le_bytes())
            .collect::<Vec<_>>(),
    );
    format!("{REQUEST}{encoded}")
}
fn request() -> Option<PathBuf> {
    let requests = std::env::args()
        .filter_map(|arg| arg.strip_prefix(REQUEST).map(str::to_owned))
        .collect::<Vec<_>>();
    if requests.is_empty() {
        return None;
    }
    assert_eq!(requests.len(), 1);
    let bytes = hex::decode(&requests[0]).unwrap();
    assert_eq!(bytes.len() % 2, 0);
    let mut units = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|b| u16::from_le_bytes([b[0], b[1]]))
        .collect::<Vec<_>>();
    assert_eq!(units.pop(), Some(0));
    assert!(!units.contains(&0));
    Some(OsString::from_wide(&units).into())
}
fn isolated_console() {
    let mut processes = [0; 4];
    // SAFETY: the fixed writable buffer has the advertised capacity. Do not signal
    // anything unless this is a console occupied solely by our own worker.
    assert_eq!(
        unsafe { GetConsoleProcessList(processes.as_mut_ptr(), processes.len() as u32) },
        1
    );
    assert_eq!(processes[0], std::process::id());
}
fn signal() {
    // SAFETY: callers verified the newly created private console. Group zero is
    // required for CTRL_C_EVENT; CREATE_NEW_PROCESS_GROUP would disable Ctrl+C.
    check(unsafe { GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0) });
}

/// A controlled child used only to validate the process-control apparatus on a
/// workstation. It does not access any registry key or call the query engine.
fn producer() -> ! {
    let cancelled = Arc::new(AtomicBool::new(false));
    let signal = cancelled.clone();
    ctrlc::set_handler(move || signal.store(true, Ordering::SeqCst)).unwrap();
    let mut stdout = io::stdout().lock();
    for index in 0..WIDTH * VALUES {
        if cancelled.load(Ordering::SeqCst) {
            eprintln!("search canceled");
            std::process::exit(130);
        }
        if let Err(error) = writeln!(stdout, "  VALUE Payload{index} 节点 {}", "x".repeat(200))
            .and_then(|_| stdout.flush())
        {
            eprintln!("output failed: Win32 {}", error.raw_os_error().unwrap_or(0));
            std::process::exit(2);
        }
    }
    std::process::exit(0)
}

#[test]
fn isolated_console_probe() {
    if let Some(directory) = request() {
        let mode = fs::read_to_string(directory.join("request.txt")).unwrap();
        if mode == "producer" {
            producer();
        }
        let result = std::panic::catch_unwind(|| {
            isolated_console();
            // A test runner/shell may pass down the inheritable ignore flag.
            // Normalize only this new console worker, never the caller. Child
            // probes/CLI inherit enabled Ctrl+C, as in an ordinary console.
            // SAFETY: no callback pointer; FALSE restores this process's handling.
            check(unsafe { SetConsoleCtrlHandler(None, 0) });
            match mode.as_str() {
                "probe" => {
                    let seen = Arc::new(AtomicBool::new(false));
                    let received = seen.clone();
                    ctrlc::set_handler(move || received.store(true, Ordering::SeqCst)).unwrap();
                    signal();
                    let started = Instant::now();
                    while !seen.load(Ordering::SeqCst) {
                        assert!(
                            started.elapsed() < Duration::from_secs(5),
                            "Ctrl+C was not delivered"
                        );
                        thread::sleep(Duration::from_millis(5));
                    }
                    let mut record = format!(
                        "PROBE generated_CTRL_C_EVENT=received elapsed_us={}\n",
                        started.elapsed().as_micros()
                    );
                    let producer = tempfile::tempdir().unwrap();
                    fs::write(producer.path().join("request.txt"), "producer").unwrap();
                    record.push_str("CONTROL_PROBE constructed producer, not a registry query\n");
                    record.push_str(&exercise(
                        || {
                            let mut command = Command::new(std::env::current_exe().unwrap());
                            command
                                .args(["--exact", WORKER, "--nocapture", "--test-threads=1"])
                                .arg(request_argument(producer.path()));
                            spawn(command)
                        },
                        &directory.join("progress.txt"),
                    ));
                    producer.close().unwrap();
                    record
                }
                "stall" => {
                    thread::sleep(Duration::from_secs(60));
                    unreachable!("watchdog did not kill worker")
                }
                "vm" => vm_queries(&directory),
                _ => panic!("unknown process worker request"),
            }
        });
        fs::write(
            directory.join("result.txt"),
            match &result {
                Ok(record) => record.clone(),
                Err(error) => format!(
                    "FAIL {}",
                    error
                        .downcast_ref::<String>()
                        .map(String::as_str)
                        .or_else(|| error.downcast_ref::<&str>().copied())
                        .unwrap_or("non-string panic")
                ),
            },
        )
        .unwrap();
        if let Err(error) = result {
            std::panic::resume_unwind(error);
        }
        return;
    }
    let directory = tempfile::Builder::new()
        .prefix("regqry-process 空间 ")
        .tempdir()
        .unwrap();
    fs::write(directory.path().join("request.txt"), "probe").unwrap();
    assert!(!hidden_worker(directory.path(), Duration::from_secs(120)));
    let record = fs::read_to_string(directory.path().join("result.txt")).unwrap();
    assert!(record.contains("generated_CTRL_C_EVENT=received"));
    println!("{record}");
    fs::remove_file(directory.path().join("result.txt")).unwrap();
    fs::write(directory.path().join("request.txt"), "stall").unwrap();
    assert!(hidden_worker(directory.path(), Duration::from_millis(300)));
    assert!(!directory.path().join("result.txt").exists());
    println!("PROBE hidden worker watchdog terminated its job");
    directory.close().unwrap();
}

/// Each actual CLI is additionally reaped on assertion failure before its handles
/// are released; the enclosing worker job is a second, independent boundary.
struct Query(Child);
impl Drop for Query {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
fn spawn(mut command: Command) -> Query {
    Query(
        command
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    )
}
fn wait(query: &mut Query) -> i32 {
    let start = Instant::now();
    loop {
        if let Some(status) = query.0.try_wait().unwrap() {
            return status.code().unwrap();
        }
        assert!(
            start.elapsed() < Duration::from_secs(30),
            "CLI watchdog expired; not a cancellation success"
        );
        thread::sleep(Duration::from_millis(5));
    }
}
fn peak(query: &Query) -> usize {
    let mut memory = PROCESS_MEMORY_COUNTERS {
        cb: std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32,
        ..Default::default()
    };
    // SAFETY: Child owns a process handle with query access; writable structure has its exact size.
    check(unsafe {
        K32GetProcessMemoryInfo(
            query.0.as_raw_handle(),
            &mut memory,
            std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32,
        )
    });
    memory.PeakWorkingSetSize
}
fn rest(mut reader: impl Read) -> Vec<u8> {
    let mut bytes = Vec::new();
    reader.read_to_end(&mut bytes).unwrap();
    bytes
}

fn trace(path: &Path, line: &str) {
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .unwrap()
        .write_all(line.as_bytes())
        .unwrap();
}

fn exercise(mut make_query: impl FnMut() -> Query, log: &Path) -> String {
    let mut records = String::new();
    for mode in ["stream", "ctrl-c", "closed-pipe"] {
        trace(log, &format!("START {mode}\n"));
        isolated_console();
        let start = Instant::now();
        let mut query = make_query();
        let mut stdout = BufReader::with_capacity(1, query.0.stdout.take().unwrap());
        let stderr = query.0.stderr.take().unwrap();
        let errors = thread::spawn(move || rest(stderr));
        // Read a complete actual VALUE record, not just the grouping header.
        // Do not keep draining yet: finite pipe capacity provides deterministic
        // backpressure even on a fast machine, without a product delay/test hook.
        let (sender, receiver) = mpsc::channel();
        let first = thread::spawn(move || {
            let mut prefix = String::new();
            loop {
                let mut line = String::new();
                assert_ne!(stdout.read_line(&mut line).unwrap(), 0, "no first result");
                let value = line.starts_with("  VALUE ");
                prefix.push_str(&line);
                if value {
                    break;
                }
            }
            sender.send((stdout, prefix)).unwrap();
        });
        let (stdout, prefix) = receiver.recv_timeout(Duration::from_secs(30)).unwrap();
        first.join().unwrap();
        let first_us = start.elapsed().as_micros();
        trace(
            log,
            &format!(
                "FIRST pid={} elapsed_us={first_us} {prefix:?}\n",
                query.0.id()
            ),
        );
        assert!(prefix.contains("节点"), "UTF-8 was not preserved");
        assert!(
            query.0.try_wait().unwrap().is_none(),
            "query exited before its stream was drained"
        );
        let cancel_start = Instant::now();
        let remaining = if mode == "closed-pipe" {
            drop(stdout);
            None
        } else {
            if mode == "ctrl-c" {
                signal();
            }
            Some(thread::spawn(move || rest(stdout)))
        };
        let code = wait(&mut query);
        let elapsed = start.elapsed().as_micros();
        let cancel_us = cancel_start.elapsed().as_micros();
        let memory = peak(&query);
        let stderr = String::from_utf8(errors.join().unwrap()).unwrap();
        let mut output = prefix.into_bytes();
        if let Some(reader) = remaining {
            output.extend(reader.join().unwrap());
        }
        let output = String::from_utf8(output).unwrap();
        let values = output.matches("  VALUE ").count();
        trace(
            log,
            &format!("OBSERVED {mode} exit={code} values={values} stderr={stderr:?}\n"),
        );
        match mode {
            "stream" => {
                assert_eq!(code, 0);
                assert!(stderr.is_empty());
                assert_eq!(values, WIDTH * VALUES);
            }
            "ctrl-c" => {
                assert_eq!(code, 130, "{stderr}");
                assert!(stderr.contains("search canceled"));
                assert!(values < WIDTH * VALUES);
            }
            "closed-pipe" => {
                assert_eq!(code, 2, "{stderr}");
                assert!(
                    stderr.contains("Win32 109") || stderr.contains("Win32 232"),
                    "{stderr}"
                );
            }
            _ => unreachable!(),
        }
        records.push_str(&format!("METRIC scenario={mode} exit={code} first_result_us={first_us} total_us={elapsed} peak_working_set_bytes={memory} values_observed={values} cancel_to_exit_us={}\nSTDERR {stderr}\n", if mode == "ctrl-c" { cancel_us } else { 0 }));
    }
    records
}

fn cli(args: &[&str]) -> Query {
    let bin = std::env::var_os("REGQRY_TEST_BIN").expect("runner must bind the actual bundled CLI");
    let mut command = Command::new(bin);
    command.args(args);
    spawn(command)
}

fn vm_queries(directory: &Path) -> String {
    let context = Context::require("query");
    let root = context.machine(KEY_WOW64_64KEY);
    for name in ["Bulk", "Long"] {
        let key = root
            .open_subkey_with_options_flags(
                name,
                REG_OPTION_OPEN_LINK,
                KEY_QUERY_VALUE | KEY_WOW64_64KEY,
            )
            .unwrap();
        assert_marker(&key, &context.nonce);
    }
    // This installs a function, not the inheritable NULL/TRUE ignore attribute.
    ctrlc::set_handler(|| {}).unwrap();
    let path = machine_path(&context, "Bulk");
    let args = [
        "--key-root",
        &path,
        "--view",
        "64",
        "--name",
        "^Payload[0-7]$",
    ];
    let mut records = String::from("ACTUAL_CLI fresh VM fixture, native view 64\n");
    records.push_str(&format!(
        "FIXTURE version=1 keys={WIDTH} values_per_key={VALUES}\nARGS {args:?}\n"
    ));
    let log = directory.join("progress.txt");
    trace(&log, &records);
    records.push_str(&exercise(|| cli(&args), &log));
    let long = machine_path(&context, "Long");
    for (pattern, expected) in [("END-OF-LARGE-VALUE$", 0), ("never-present", 1)] {
        trace(&log, &format!("LONG_ARGS root={long:?} data={pattern:?}\n"));
        records.push_str(&format!(
            "ARGS {:?}\n",
            ["--key-root", &long, "--view", "64", "--data", pattern]
        ));
        let mut query = cli(&["--key-root", &long, "--view", "64", "--data", pattern]);
        let stdout = query.0.stdout.take().unwrap();
        let stderr = query.0.stderr.take().unwrap();
        let output = thread::spawn(move || rest(stdout));
        let errors = thread::spawn(move || rest(stderr));
        assert_eq!(wait(&mut query), expected);
        assert!(errors.join().unwrap().is_empty());
        let output = String::from_utf8(output.join().unwrap()).unwrap();
        if expected == 0 {
            assert!(
                output.contains(&"界".repeat(6000)),
                "value name was truncated"
            );
            assert!(output.contains("[preview truncated]"));
            assert!(output.contains("(1048614 bytes)"));
            assert!(
                !output.contains("END-OF-LARGE-VALUE"),
                "needle should be beyond the preview"
            );
            records.push_str("LONG saved_bytes=1048614 value_name_utf16_units=6000 needle_after_preview=matched\n");
        } else {
            assert!(output.is_empty());
            records.push_str("NO_MATCH stdout=empty stderr=empty exit=1\n");
        }
    }
    let args = [
        "--key-root",
        &long,
        "--view",
        "64",
        "--name",
        "^A\nB\t\u{1b}$",
    ];
    records.push_str(&format!("ARGS {args:?}\n"));
    let mut query = cli(&args);
    let stdout = query.0.stdout.take().unwrap();
    let stderr = query.0.stderr.take().unwrap();
    let output = thread::spawn(move || rest(stdout));
    let errors = thread::spawn(move || rest(stderr));
    assert_eq!(wait(&mut query), 0);
    assert!(errors.join().unwrap().is_empty());
    let output = String::from_utf8(output.join().unwrap()).unwrap();
    assert!(output.contains(r#"VALUE "A\nB\t\u{1B}""#));
    assert!(output.contains(r#""行一\n行二\t\u{1B}""#));
    assert!(!output.contains('\u{1b}'));
    assert_eq!(output.matches("  VALUE ").count(), 1);
    records.push_str(&format!("CONTROL_NAME exit=0 STDOUT {output}\n"));
    records
}

#[test]
#[ignore = "explicit disposable VM: real CLI streaming, Ctrl+C, closed pipeline and long values"]
fn vm_cli_processes() {
    let context = Context::require("query");
    context.machine(KEY_WOW64_64KEY);
    let directory = tempfile::Builder::new()
        .prefix("regqry-process 空间 ")
        .tempdir()
        .unwrap();
    fs::write(directory.path().join("request.txt"), "vm").unwrap();
    assert!(!hidden_worker(directory.path(), Duration::from_secs(150)));
    let record = fs::read_to_string(directory.path().join("result.txt")).unwrap();
    assert!(record.contains("scenario=ctrl-c exit=130"));
    assert!(record.contains("scenario=closed-pipe exit=2"));
    assert!(record.contains("needle_after_preview=matched"));
    println!("{record}");
    println!(
        "TRACE {}",
        fs::read_to_string(directory.path().join("progress.txt")).unwrap()
    );
    directory.close().unwrap();
}
