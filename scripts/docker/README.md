# Docker, Nerdctl, Podman

### dx
Run a container with preset using `dx`

Presets can be defined in the `$env.CNTRCONFIG` file, with the content as follows:

```yaml
preset:
- name: rust
  image: rust
  cmd: []
  env:
    CARGO_HOME: /opt/cargo
  volumes:
    .: /world
    ~/.cargo: /opt/cargo
  port:
    '8000': 80
  cmd: []
  args:
  - --cap-add=SYS_ADMIN
  - --cap-add=SYS_PTRACE
  - --security-opt
  - seccomp=unconfined
```
- specify the `container_name` field, delete the existing container if it exists and then run.

---
[Others](https://github.com/orbsh/nushell/blob/main/README.md)
