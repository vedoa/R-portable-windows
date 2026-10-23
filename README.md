# Portable R for Windows

Build isolated x64 Windows packages for R 4.6.1, R 4.5.3, and R 4.4.3. Each package uses the corresponding CRAN binary and limits R library lookup to its bundled library. Cleanup removes top-level documentation/tests, Tcl/Tk support, locale data, installer metadata, and package demo, help, documentation, HTML, test, and translation folders, while retaining every bundled package directory and R support components such as `Rcmd.exe`, headers, and source. Plotting packages (`graphics`, `grDevices`, `grid`, and `lattice`) remain installed, but package help and examples are removed. The final uncompressed size is reported during the build and can vary by R version. Archives use `R-portable-<R-version>-<short-commit>-x64.zip`; the short commit hash distinguishes rebuilds of the same R version.

## Production builds

The production build logic is in `Build-PortableR.ps1` and `.github/workflows/build-portable-r.yml`. GitHub Actions builds all three versions on a `windows-latest` matrix. Pushing any tag, with or without a `v` prefix (for example, `4.6.1`), publishes the three versioned archives together to that tag's GitHub Release. The workflow can also be started manually to create build artifacts.

## Local Sandbox testing

Local-only testing files are grouped under `local/`, separately from the production build files. On Windows with Windows Sandbox available, launch the local test with:

```powershell
.\local\Run-Sandbox.ps1
```

The launcher resolves the `local` directory from its own location, updates the `HostFolder` in `local\TestEnv.wsb`, writes a temporary configuration file, and starts Windows Sandbox. The writable mapping exposes `local/` inside the Sandbox as `C:\R-portable-windows`; the logon command runs `Test-PortableR.ps1` with its default version, R 4.6.1. Generated `R-portable-*` runtime directories remain under `local/` and are excluded by `local/.gitignore`.

To test another supported version from a PowerShell prompt inside the mapped Sandbox folder, run:

```powershell
.\Test-PortableR.ps1 -RVersion 4.5.3
.\Test-PortableR.ps1 -RVersion 4.4.3
```

The test script announces each CRAN download while suppressing PowerShell's per-request progress rendering, shows extraction status, installs and strips the runtime, then verifies the R version and bundled library path.

## Licensing and attribution

This project's original scripts and workflow are distributed under the GNU General Public License, version 3 (GPL-3.0), as provided in [`LICENSE`](LICENSE). GPL-3.0 is a copyleft license: when redistributing covered work, preserve the license and provide the corresponding source as required by its terms.

The bundled R binaries for versions 4.6.1, 4.5.3, and 4.4.3 are provided by the R Project for Statistical Computing through CRAN. They are upstream software, not authored by this project, and are distributed under their applicable GPL terms. Source code and license information are available from [CRAN](https://cran.r-project.org/) and the [R Project](https://www.r-project.org/).