# Patches for PHP 7.3.31

Applied in file-name order on top of `php/php-src` tag `php-7.3.31`.

| File | Fixes | Origin |
|---|---|---|
| `0000-backport-ZSTR_MAX_LEN.patch` | prerequisite: defines `ZSTR_MAX_OVERHEAD`/`ZSTR_MAX_LEN` in `Zend/zend_string.h` (as in PHP 7.4), used by the concat overflow checks of the php2shell patch | [shivammathur/php-src-backports@37056ad](https://github.com/shivammathur/php-src-backports/commit/37056ad63) |
| `0001-Avoid-state-corruption-via-bailout-on-PHP-7.3.patch` | CVE-2026-109618 (GHSA-w8hw-w9fx-j79w), CVE-2026-109619 (GHSA-6wmf-4rv5-p3rp) — "php2shell" | [shivammathur/php-src-backports@7e6d6d3](https://github.com/shivammathur/php-src-backports/commit/7e6d6d39a3897cfc7785966e1217d5cbf47eefd8), a backport of upstream [php/php-src@712e60f](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2) (PHP 7.4) / [php/php-src@3584a98](https://github.com/php/php-src/commit/3584a98bda0f2c0d367255b046798b0d3a221a19) (PHP 8.2) |

SHA-256 of `0000-backport-ZSTR_MAX_LEN.patch` as imported: `90ee3096cd75dd2025f933ae70ac1db65659e45f9571f49536f1a98c6048d1c1`

SHA-256 of `0001-…` as imported: `448fd204ae9dbbbb7f64f951828c7a18850450ffc47dd5880a77747b6d9a85df`

Both patches apply cleanly to 7.3.31 (`git apply --check`, offsets only in `main/main.c` and `main/php_variables.c`).
Upstream 7.3.32 and 7.3.33 are **not** included on purpose: they only change FPM (CVE-2021-21703, not built on Windows) and
XML special-character handling in file names (CVE-2021-21707); the goal of this build is an exact 7.3.31 with the php2shell fix.
