# Lab 04: Deny by argument, allow by name

**Goal:** deny only the dangerous case, and allow known good programs.

> **Save point 04:** This directory is the completed state after the AF_ALG argument policy.
> Follow the slides in `labs/work`. Copy this directory there only to recover.

New in `hello_lsm.bpf.c`:

- The decision uses a hook **argument**. The program looks only at binds to an `AF_ALG` address.
  Normal network sockets do not change.
- The policy is the opposite of lab 03. Lab 03 denies one name. This lab denies AF_ALG binds for all programs
  **except** the names on an allow list (`trusted-app` and `cryptsetup`).

## Run the save point

```sh
make load
../tools/try-bind inet                       # OK: not AF_ALG
../tools/try-bind alg hash sha256            # Operation not permitted
../tools/try-bind alg aead 'authencesn(hmac(sha256),cbc(aes))'   # Operation not permitted

cp ../tools/try-bind ../tools/trusted-app
../tools/trusted-app alg hash sha256         # OK: on the allow list
make unload
```

## What to look at

- This lab already stops Copy Fail. The exploit cannot bind its AEAD socket.
- It denies too much. `alg hash sha256` is not related to the bug. Some programs use AF_ALG
  hashes and ciphers for good reasons.
- An attacker can go around the allow list. You did this when you copied a file to the name
  `trusted-app`. An attacker can also call `prctl(PR_SET_NAME, "trusted-app")`, without a copy.

Lab 05 fixes these two problems.
