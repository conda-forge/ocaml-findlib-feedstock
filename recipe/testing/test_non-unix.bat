@echo off
setlocal enabledelayedexpansion

echo === non-unix test suite for ocaml-findlib ===

:: Debug: Show what ocamlfind sees
echo === DEBUG: Environment ===
echo CONDA_PREFIX=%CONDA_PREFIX%
echo OCAMLFIND_CONF=%OCAMLFIND_CONF%
echo OCAMLLIB=%OCAMLLIB%

echo === DEBUG: findlib.conf contents ===
if exist "%CONDA_PREFIX%\Library\etc\findlib.conf" (
    type "%CONDA_PREFIX%\Library\etc\findlib.conf"
) else (
    echo findlib.conf not found at %CONDA_PREFIX%\Library\etc\findlib.conf
)

echo === DEBUG: ocamlfind printconf ===
ocamlfind printconf 2>&1

echo === DEBUG: Check ALL META files in site-lib ===
for /d %%d in ("%CONDA_PREFIX%\Library\lib\ocaml\site-lib\*") do (
    if exist "%%d\META" (
        echo --- %%~nxd/META ---
        type "%%d\META"
        echo.
    )
)
echo === DEBUG: Check bytes META specifically ===
if exist "%CONDA_PREFIX%\Library\lib\ocaml\site-lib\bytes\META" (
    echo --- First 50 bytes hex dump ---
    powershell -Command "Format-Hex -Path '%CONDA_PREFIX%\Library\lib\ocaml\site-lib\bytes\META' | Select-Object -First 5"
    echo --- Content ---
    type "%CONDA_PREFIX%\Library\lib\ocaml\site-lib\bytes\META"
) else (
    echo bytes/META not found
)
echo === DEBUG: Check findlib.conf hex ===
powershell -Command "Format-Hex -Path '%CONDA_PREFIX%\Library\etc\findlib.conf' | Select-Object -First 5"

:: Basic help test
echo Testing ocamlfind install -help...
ocamlfind install -help
if errorlevel 1 (
    echo ocamlfind install -help: FAILED
    exit /b 1
)

:: Basic functionality tests
echo Testing ocamlfind printconf...
ocamlfind printconf
if errorlevel 1 (
    echo ocamlfind printconf: FAILED
    exit /b 1
)

ocamlfind printconf conf
if errorlevel 1 (
    echo ocamlfind printconf conf: FAILED
    exit /b 1
)

ocamlfind printconf path
if errorlevel 1 (
    echo ocamlfind printconf path: FAILED
    exit /b 1
)

ocamlfind printconf stdlib
if errorlevel 1 (
    echo ocamlfind printconf stdlib: FAILED
    exit /b 1
)

:: List installed packages
echo Testing ocamlfind list...
ocamlfind list
if errorlevel 1 (
    echo ocamlfind list: FAILED
    exit /b 1
)

:: Query findlib package metadata
echo Testing ocamlfind query...
ocamlfind query findlib
if errorlevel 1 (
    echo ocamlfind query findlib: FAILED
    exit /b 1
)

ocamlfind query findlib -format "%%v"
if errorlevel 1 (
    echo ocamlfind query findlib -format: FAILED
    exit /b 1
)

:: Verify configuration file is readable
echo Checking configuration file...
if exist "%CONDA_PREFIX%\Library\etc\findlib.conf" (
    echo Found: %CONDA_PREFIX%\Library\etc\findlib.conf
) else (
    echo Configuration file not found
    exit /b 1
)

:: Test ocamlfind can locate OCaml compiler
echo Testing ocamlfind ocamlc/ocamlopt...
ocamlfind ocamlc -version
if errorlevel 1 (
    echo ocamlfind ocamlc -version: FAILED
    exit /b 1
)

ocamlfind ocamlopt -version
if errorlevel 1 (
    echo ocamlfind ocamlopt -version: FAILED
    exit /b 1
)

:: Test compilation with ocamlfind (simple program)
echo Testing bytecode compilation...
echo print_endline "Hello from ocamlfind"> test_hello.ml
ocamlfind ocamlc -o test_hello.exe test_hello.ml
if errorlevel 1 (
    echo Bytecode compilation: FAILED
    exit /b 1
)
test_hello.exe
if errorlevel 1 (
    echo Bytecode execution: FAILED
    exit /b 1
)

:: Test native compilation
echo Testing native compilation...
ocamlfind ocamlopt -o test_hello_opt.exe test_hello.ml
if errorlevel 1 (
    echo Native compilation: FAILED
    exit /b 1
)
test_hello_opt.exe
if errorlevel 1 (
    echo Native execution: FAILED
    exit /b 1
)

:: Cleanup
del /q test_hello.ml test_hello.exe test_hello_opt.exe *.cmi *.cmo *.cmx *.o 2>nul

echo === All non-unix tests passed ===
exit /b 0
