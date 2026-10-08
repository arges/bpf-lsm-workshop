# Quickstart: Validating the Labs

Prerequisite: a built workshop image (`make image`).

## Automated

```sh
make test
```

Expected: `SMOKE-TEST-PASS` followed by one line per lab and `LABS-TEST-PASS`.

## By hand

Copy `labs/` into a running VM (`make run`, then from another terminal
`tar -cf - labs | scripts/ssh-vm.sh 'tar -xf -'`), log in, and follow each lab's README in order.
What each one should show:

| Lab | Action | Expected |
|---|---|---|
| 01 | `tools/try-bind inet` with the program loaded | hello line in `make trace`; bind OK |
| 02 | same | `bind(): comm=try-bind pid=… family=2` |
| 03 | `nc -l 127.0.0.1 9999` | Operation not permitted; `try-bind inet` still OK |
| 04 | `try-bind alg hash sha256` | Operation not permitted; OK when run as `trusted-app` |
| 05 | `try-bind alg aead 'authencesn(hmac(sha256),cbc(aes))'` | denied; `alg hash sha256` OK; allowed for the `--allow` file; denied for a same-named copy elsewhere; `--audit` denies nothing |
