use super::*;
use std::{sync::mpsc, time::Duration};

fn private_hive(test: impl FnOnce(&RegKey)) {
    let temp = tempfile::tempdir().unwrap();
    {
        let hive = RegKey::load_app_key(temp.path().join("fixture.hiv"), true).unwrap();
        test(&hive);
    }
    temp.close().unwrap();
}

fn set_raw(key: &RegKey, name: &OsStr, kind: u32, bytes: &[u8]) -> io::Result<()> {
    let name: Vec<_> = name.encode_wide().chain(Some(0)).collect();
    // SAFETY: the handle belongs to this test's private application hive. Both
    // buffers remain live for the call, with the exact initialized byte length.
    let code = unsafe {
        Registry::RegSetValueExW(
            key.raw_handle(),
            name.as_ptr(),
            0,
            kind,
            bytes.as_ptr(),
            u32::try_from(bytes.len()).unwrap(),
        )
    };
    if code == ERROR_SUCCESS {
        Ok(())
    } else {
        Err(io::Error::from_raw_os_error(code as i32))
    }
}

#[test]
fn native_rewrites_between_attempts_return_only_the_successful_type_and_saved_length() {
    for exhaust in [false, true] {
        private_hive(|hive| {
            let key = hive.create_subkey("Changing").unwrap().0;
            let writer_key = key
                .open_subkey_with_flags("", Registry::KEY_SET_VALUE)
                .unwrap();
            let cancelled = AtomicBool::new(false);
            std::thread::scope(|scope| {
                let (requests, changes) = mpsc::channel::<(u32, Vec<u8>)>();
                let (finished, responses) = mpsc::channel();
                let writer = scope.spawn(move || {
                    for (kind, bytes) in changes {
                        finished
                            .send(set_raw(&writer_key, OsStr::new("Data"), kind, &bytes))
                            .unwrap();
                    }
                });
                let mut calls = 0;
                let mut capacities = Vec::new();
                let actual = buffered(&cancelled, 256, |buffer| {
                    calls += 1;
                    capacities.push(buffer.len());
                    let (kind, bytes) = if !exhaust && calls == 3 {
                        // Shrink and change type after two real ERROR_MORE_DATA
                        // responses. No stale bytes or type from either failed
                        // attempt may become part of the successful result.
                        (0xF00D, vec![0xA5, 0, 0xFF])
                    } else {
                        (Registry::REG_BINARY, vec![calls as u8; buffer.len() + 1])
                    };
                    requests.send((kind, bytes)).unwrap();
                    responses
                        .recv_timeout(Duration::from_secs(10))
                        .unwrap()
                        .unwrap();
                    query_value(&key, OsStr::new("Data"), buffer)
                });
                drop(requests);
                writer.join().unwrap();
                println!(
                    "native rewrite: exhaust={exhaust}, calls={calls}, capacities={capacities:?}"
                );
                if exhaust {
                    assert_eq!(calls, 9, "initial attempt plus exactly eight retries");
                    let error = actual.unwrap_err();
                    assert!(error.to_string().contains("eight retries"), "{error}");
                    assert!(!confirmed_value_missing(&error));
                    // The same value remains fully readable once mutation stops.
                    let saved = WindowsSource {
                        cancelled: &cancelled,
                    }
                    .read(&key, OsStr::new("Data"))
                    .unwrap();
                    assert_eq!(saved.bytes, vec![9; capacities[8] + 1]);
                } else {
                    let (mut bytes, (kind, length)) = actual.unwrap();
                    bytes.truncate(length);
                    assert_eq!(calls, 3);
                    assert_eq!(kind, 0xF00D);
                    assert_eq!(bytes, [0xA5, 0, 0xFF]);
                }
            });
        });
    }
}

#[test]
fn native_deletion_and_cancellation_stop_retrying_without_becoming_enumeration_end() {
    for event in ["delete value", "delete key", "cancel"] {
        private_hive(|hive| {
            let key = hive.create_subkey("Changing").unwrap().0;
            set_raw(
                &key,
                OsStr::new("Data"),
                Registry::REG_BINARY,
                &vec![1; 513],
            )
            .unwrap();
            let cancelled = AtomicBool::new(false);
            let mut calls = 0;
            let error = buffered(&cancelled, 256, |buffer| {
                calls += 1;
                let result = query_value(&key, OsStr::new("Data"), buffer)?;
                if calls == 1 {
                    assert!(matches!(result, BufferRead::More(_)));
                    match event {
                        "delete value" => key.delete_value("Data").unwrap(),
                        "delete key" => hive.delete_subkey("Changing").unwrap(),
                        "cancel" => cancelled.store(true, AtomicOrdering::Relaxed),
                        _ => unreachable!(),
                    }
                }
                Ok(result)
            })
            .unwrap_err();
            println!(
                "native retry interruption: event={event}, calls={calls}, error={}",
                error_text(&error)
            );
            match event {
                "cancel" => {
                    assert_eq!(calls, 1);
                    assert_eq!(error.kind(), io::ErrorKind::Interrupted);
                }
                "delete value" => {
                    assert_eq!(calls, 2);
                    assert_eq!(error.raw_os_error(), Some(2));
                }
                "delete key" => {
                    assert_eq!(calls, 2);
                    assert_eq!(error.raw_os_error(), Some(1018));
                    assert!(!confirmed_value_missing(&error));
                    let native = WindowsSource {
                        cancelled: &cancelled,
                    };
                    assert_eq!(
                        native.child_at(&key, 0).err().unwrap().raw_os_error(),
                        Some(1018)
                    );
                    assert_eq!(
                        native.value_at(&key, 0).unwrap_err().raw_os_error(),
                        Some(1018)
                    );
                }
                _ => unreachable!(),
            }
        });
    }
}

#[test]
fn native_name_retries_preserve_all_utf16_units_and_only_no_more_items_ends_a_list() {
    private_hive(|hive| {
        let child_name = OsString::from_wide(&vec![0x4E2D; 255]);
        let key = hive.create_subkey(&child_name).unwrap().0;
        let value_name = OsString::from_wide(&[vec![0x4E2D; 6000], vec![0xD800]].concat());
        set_raw(&key, &value_name, 0xF00D, &[0xFE]).unwrap();
        let cancelled = AtomicBool::new(false);
        let mut attempts = 0;
        let (name, child) = buffered(&cancelled, 1, |buffer| {
            attempts += 1;
            enum_key(hive, 0, buffer)
        })
        .unwrap();
        let (length, modified) = child.unwrap();
        assert_eq!(OsString::from_wide(&name[..length]), child_name);
        assert_eq!(attempts, 9);
        assert_ne!(modified, 0);
        let (name, length) =
            buffered(&cancelled, 256, |buffer| enum_value(&key, 0, buffer)).unwrap();
        assert_eq!(OsString::from_wide(&name[..length.unwrap()]), value_name);
        let native = WindowsSource {
            cancelled: &cancelled,
        };
        assert_eq!(native.value_at(&key, 0).unwrap().unwrap(), value_name);
        assert!(native.child_at(hive, 1).unwrap().is_none());
        assert!(native.value_at(&key, 1).unwrap().is_none());
        assert_eq!(native.read(&key, &value_name).unwrap().bytes, [0xFE]);
    });
}

#[test]
fn cancellation_and_capacity_overflow_fail_before_an_operation_can_run() {
    for (cancel, initial) in [
        (true, 256),
        (false, usize::MAX),
        (false, u32::MAX as usize + 1),
    ] {
        let cancelled = AtomicBool::new(cancel);
        let mut calls = 0;
        let error = buffered::<u8, ()>(&cancelled, initial, |_| {
            calls += 1;
            Ok(BufferRead::Done(()))
        })
        .unwrap_err();
        assert_eq!(calls, 0);
        if cancel {
            assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        } else {
            assert!(error.to_string().contains("capacity overflow"));
        }
    }
    let cancelled = AtomicBool::new(false);
    let error =
        buffered::<u16, ()>(&cancelled, 256, |_| Ok(BufferRead::More(usize::MAX))).unwrap_err();
    assert!(error.to_string().contains("capacity overflow"));
    let error = buffered::<u8, ()>(&cancelled, 256, |_| {
        cancelled.store(true, AtomicOrdering::Relaxed);
        Ok(BufferRead::More(usize::MAX))
    })
    .unwrap_err();
    assert_eq!(
        error.kind(),
        io::ErrorKind::Interrupted,
        "cancel before any further allocation"
    );
}
