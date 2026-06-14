# ghostty-vt-static

Pre-built static [libghostty-vt](https://github.com/ghostty-org/ghostty)
libraries for the [Jax editor](https://github.com/jax-editor/jax).

libghostty-vt is the embeddable VT-parsing core of the Ghostty terminal
emulator. It has no stable upstream release line for embedding consumers
— we pin a specific commit and publish platform-specific tarballs as
GitHub releases. The jax build downloads the appropriate tarball at
build time, eliminating a Zig toolchain dependency from every downstream
consumer's CI and developer machine.

## Platforms

| Artifact suffix              | Runner            |
|------------------------------|-------------------|
| `linux-x86_64.tar.gz`        | `ubuntu-24.04`    |
| `linux-aarch64.tar.gz`       | `ubuntu-24.04-arm`|
| `macos-aarch64.tar.gz`       | `macos-14`        |

## Release contents

Each tarball extracts to:

```
ghostty-vt-static-<version>-<platform>-<arch>/
├── lib/
│   ├── libghostty-vt.a
│   ├── libhighway.a
│   └── libsimdutf.a
└── include/
    └── ghostty/
        └── *.h
```

## Versioning

Tags follow `vN-<short-commit>`:

- `N` is a **monotonic build counter that never resets**. It is not
  tied to any upstream version — ghostty's embedded VT library has no
  stable release line. Bump on any release-affecting change: new
  upstream pin, build-script tweak, repack-step change, etc.
- `<short-commit>` is the 7-char prefix of the pinned upstream ghostty
  commit (see `ghostty-commit`).

Example: `v1-1547dd6`, `v2-1547dd6` (build script tweak, same upstream),
`v3-5659cef4` (upstream pin moved).

The `vN` prefix keeps tags sortable as plain strings.

## macOS archive alignment workaround

Zig 0.15.x's bundled `ar` lays out archive members without 8-byte
alignment, which the current Apple `ld` rejects with:

```
ld: 64-bit mach-o member 'libhighway_zcu.o' not 8-byte aligned
    in 'ghostty-vt-static/lib/libhighway.a'
```

The fix landed in Zig master post-0.15 but is not backported. Ghostty
pins `minimum_zig_version = "0.15.2"` and uses 0.15-only build APIs, so
a Zig upgrade is blocked at both ends. As a workaround, the macOS leg
of the release pipeline re-archives each `.a` with system `ar` + `ranlib`
after `zig build` finishes. System `ar` correctly aligns members.

Once ghostty adopts a Zig version with the alignment fix, the repack
step becomes dead weight — `build.sh` will guard it and fail loudly so
we don't ship it indefinitely.

## Building a release

```bash
./tag-release.sh
```

Bumps the build counter, tags `vN-<commit>`, and pushes. The GitHub
Actions workflow builds all platforms and attaches tarballs to a
release.

## Manual local build

The build is wrapped in a Nix flake so toolchain versions are pinned in
`flake.lock` (zig 0.15.2, cmake, ninja, git from a pinned nixpkgs
commit). This is the same path CI uses.

```bash
nix develop --command ./build.sh
ls out/lib/libghostty-vt.a
```

Without Nix (matches what was in CI before): install zig 0.15.2 + cmake
+ ninja yourself (e.g. `brew install zig@0.15 cmake ninja`), then run
`./build.sh` directly. The script enforces a `command -v` check on each
tool so misconfiguration fails fast.

## Updating the upstream pin

1. Edit `ghostty-commit` — replace with the new full SHA
2. Test locally: `rm -rf /tmp/ghostty-vt-static-build && nix develop --command ./build.sh`
3. Commit, run `./tag-release.sh`, push

## Updating the nixpkgs pin

```bash
nix flake update
nix develop --command ./build.sh    # confirm it still builds
git commit flake.lock
```

## License

This repo's build scripts are MIT. Released artifacts contain compiled
output from upstream projects under their respective licenses:

- libghostty-vt: MIT (ghostty-org/ghostty)
- highway: Apache-2.0 (google/highway)
- simdutf: Apache-2.0 OR MIT (simdutf/simdutf)
