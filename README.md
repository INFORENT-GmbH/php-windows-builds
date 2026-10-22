# php-windows-builds

Reproducible Windows builds of PHP with security patches we need, built on GitHub-hosted
runners with the PHP project's own [php-windows-builder](https://github.com/php/php-windows-builder)
and published as [GitHub Releases](../../releases).

**Why:** end-of-life PHP versions bundled with third-party products (currently PHP 7.3.31 for
IceWarp Server on Windows) do not receive upstream Windows binaries for new vulnerabilities such as
php2shell (CVE-2026-109618, CVE-2026-109619). This repository builds exactly the bundled version plus
the required patches, from pinned sources, with a verifiable build log.

## Downloads

Every release (`php-<version>-r<N>`) contains:

| File | Content |
|---|---|
| `php-<version>-nts-Win32-<toolset>-<arch>.zip` | Standard PHP layout, non thread safe: `php.exe` (CLI), `php-cgi.exe` (CGI/FastCGI), `php-win.exe`, `php7.dll`, `ext\`, … |
| `php-<version>-Win32-<toolset>-<arch>.zip` | Same, thread safe (`php7ts.dll`) |
| `php-<version>-icewarp-<nts\|ts>-<arch>.zip` | **IceWarp layout**: `php.exe` = CGI/FastCGI binary, `php-cli.exe` = CLI binary (see below) |
| `php-debug-pack-*.zip`, `php-devel-pack-*.zip`, `php-test-pack-*.zip` | Debug symbols, headers/libs, test suite |
| `SHA256SUMS.txt` | Checksums of all files |

`BUILD-INFO.txt` inside every binary archive names the source commit, the patches with their hashes,
the builder commit and the GitHub Actions run that produced the file.

## IceWarp Server (Windows)

IceWarp runs PHP as FastCGI: it starts several instances of `<IceWarp>\php\php.exe` and talks to them
over TCP ([IceWarp docs](https://docs.icewarp.com/Content/IceWarp-Server/Administration-Nodes/Web%20Service/PHP%20Problems%20and%20Workarounds/Using%20FastCGI.htm)).
That is the behaviour of PHP's CGI binary, so in the IceWarp folder `php.exe` is `php-cgi.exe` and
`php-cli.exe` is the command line `php.exe`. The `icewarp` bundle has the files renamed accordingly.

Before replacing anything, confirm on the server which flavour (thread safety) IceWarp ships:

```powershell
& 'C:\Program Files\IceWarp\php\php.exe' -v        # expect "(cgi-fcgi) ... NTS" or "... ZTS"
& 'C:\Program Files\IceWarp\php\php-cli.exe' -v    # expect "(cli)"
Test-Path 'C:\Program Files\IceWarp\php\php7ts.dll' # True = thread safe build -> use the -ts- bundle
```

Then: stop the IceWarp services, back up the `php` folder, copy the bundle contents over it
(keep IceWarp's own `php.ini` and any extra extensions it ships; our `ext\` only contains PHP's
bundled extensions), start the services and check `php.exe -v` / `php-cli.exe -v` again plus a
WebClient login. The build date in `-v` distinguishes the patched build from the original 7.3.31.

## How a build works

```
builds/<version>/source.json   pinned php-src tag + commit, pinned builder commit
builds/<version>/patches/      *.patch applied in name order (provenance in patches/README.md)
builds/<version>/bundles.json  product bundles = file renames on top of the standard archive
scripts/*.ps1                  patch application, smoke tests, build info, bundle assembly
.github/workflows/build.yml    the pipeline
```

1. `prepare` reads the definition and builds the job matrix.
2. `build` (matrix `arch × ts`, `windows-2022`) checks out `php/php-src` at the pinned commit,
   applies the patches, and runs `php/php-windows-builder/php@<pinned sha>` from the source tree.
   The builder installs the matching Visual C++ toolset (VC15 for PHP 7.3) and the official
   dependency bundles, builds with PGO and packages like the official windows.php.net releases.
3. `package` smoke-tests every archive (version banner, thread safety, modules, `php-cgi.exe`,
   clean out-of-memory fatal error, a multipart/form-data POST through php-cgi), adds `BUILD-INFO.txt`,
   creates the bundles and `SHA256SUMS.txt`, and publishes a release when a tag was given.

A full run takes roughly 45 minutes (about 35 for the two builds).

### Running it

- **Actions → Build PHP → Run workflow**: `version` (default `7.3.31`), `arch-list`, `ts-list`,
  optional `release-tag`. Without a release tag the result is only a workflow artifact
  (`release-<version>`), useful for testing.
- **Tag push**: `git tag php-7.3.31-r1 && git push origin php-7.3.31-r1` builds `x64` × `nts,ts`
  and publishes the release.

### Adding a version or a patch

1. Create `builds/<version>/source.json` (copy an existing one; resolve the tag to a commit with
   `git rev-parse php-<version>^{commit}` in a php-src clone) and `patches/`.
2. Check locally that the patches apply: `git apply --check` on a checkout of the tag.
3. Bump the release tag suffix (`-r2`, …) when only patches change for the same PHP version.

Supported PHP versions follow php-windows-builder (7.1 and newer; the toolset per version is in its
`php/BuildPhp/config/vs.json`).

## Supply chain notes

- PHP source is checked out by commit hash, not by tag name; the builder action is pinned by hash.
- Patch files live in this repository; their origin and SHA-256 are documented in
  `builds/<version>/patches/README.md` and repeated in `BUILD-INFO.txt`.
- Builds run on GitHub-hosted `windows-2022` runners only; nothing is uploaded from developer machines.
- The build log of every release is linked in its notes.

## License

Scripts and workflows: MIT (see `LICENSE`). PHP and the produced binaries: PHP License 3.01.
