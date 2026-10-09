#!/bin/bash
# ---- Compilación de Commander3 en PhotonCluster ---- #
#
# Compila e instala Commander3 desde este repositorio con Intel oneAPI,
# para -march=x86-64-v3 (nivel común de todos los workers).
#
# Uso (desde photon11, que tiene internet para las descargas del CMake):
#   ./compilar_photon.sh <ruta_de_instalacion>
#
# Ejemplos:
#   ./compilar_photon.sh /cosmotools/commander3/$(date +%F)       # versión común (gestora)
#   ./compilar_photon.sh ~/software/commander3/mi-rama            # versión personal
#
# Variables opcionales:
#   JOBS=16 ./compilar_photon.sh ...     # núcleos para compilar (por defecto 10)
#
# La carpeta de compilación (ficheros intermedios y logs) va a ~/build/ y se
# puede borrar al terminar. Al instalar se deja un fichero COMMIT con el commit
# y la rama compilados.
#
# Una vez se termine de compilar la versión común, el gestor debe publicarla
# (<fecha> es la que indica "Commander3 instalado en ..."):
#   cd /cosmotools/commander3
#   ln -sfn <fecha> actual
#   ls -l                                   # debe mostrar "actual -> <fecha>"
#
# Y comprobar que funciona:
#   module purge
#   module load commander3/Commander
#   which commander3                        # /cosmotools/commander3/actual/bin/commander3
# ------------------------------------------------------- #

set -eo pipefail

# 1. Entorno limpio: sin conda ni el .bashrc del usuario (interfieren con CMake)
if [ -z "$PHOTON_CLEAN" ]; then
    exec env -i HOME="$HOME" TERM="$TERM" USER="$USER" PHOTON_CLEAN=1 \
        bash --noprofile --norc "$0" "$@"
fi

PREFIX="$1"
if [ -z "$PREFIX" ]; then
    echo "Uso: $0 <ruta_de_instalacion>" >&2
    exit 1
fi
case "$PREFIX" in
    /*) ;;
    *)  PREFIX="$(pwd)/$PREFIX" ;;
esac

# 2. Comprobaciones previas
if [ "$(hostname -s)" != "photon11" ]; then
    echo "Compila desde photon11: el CMake de Commander descarga dependencias de internet." >&2
    exit 1
fi

cd "$(dirname "$(readlink -f "$0")")"     # raíz del repositorio

if grep -v '^[[:space:]]*#' cmake/compilers/intel.cmake | grep -q -- '-xHost' || grep -v '^[[:space:]]*#' cmake/projects/healpix.cmake | grep -q -- '-march=native'; then
    echo "El repositorio no tiene los parches de Photon (-xHost / -march=native sin cambiar)." >&2
    echo "Actualiza tu rama desde master del fork del grupo." >&2
    exit 1
fi

if [ -d "$PREFIX" ] && [ -n "$(ls -A "$PREFIX" 2>/dev/null)" ]; then
    echo "La ruta de instalación ya existe y no está vacía: $PREFIX" >&2
    echo "Usa otra ruta (por ejemplo, con otra fecha) para no sobrescribir una versión." >&2
    exit 1
fi

# 3. Compiladores Intel oneAPI
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
source /opt/software/apps/intel/oneapi/2026.1/setvars.sh > /dev/null
ISA=x86-64-v3
JOBS="${JOBS:-10}"
umask 002                                  # el grupo puede usar lo instalado

BUILD="$HOME/build/commander-$(basename "$PREFIX")-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BUILD"

echo "Repositorio : $(pwd)  ($(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD))"
echo "Instalación : $PREFIX"
echo "Compilación : $BUILD"
echo

# 4. Configurar
cmake -S . -B "$BUILD" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DCMAKE_Fortran_COMPILER=ifx \
    -DMPI_C_COMPILER=mpiicx -DMPI_CXX_COMPILER=mpiicpx -DMPI_Fortran_COMPILER=mpiifx \
    -DUSE_SYSTEM_BLAS=ON -DBLA_VENDOR=Intel10_64lp \
    -DUSE_SYSTEM_HDF5=OFF -DUSE_SYSTEM_FFTW=OFF -DUSE_SYSTEM_CFITSIO=OFF -DUSE_SYSTEM_HEALPIX=OFF \
    -DCFITSIO_USE_CURL=OFF \
    2>&1 | tee "$BUILD/configure.log"
grep -E "Build Type|Compiler Flags" "$BUILD/configure.log"

# 5. Compilar e instalar
cmake --build "$BUILD" --target install -j "$JOBS" 2>&1 | tee "$BUILD/build.log"

# 6. Registro de lo compilado y verificación
{
    echo "commit: $(git rev-parse HEAD)"
    echo "rama:   $(git rev-parse --abbrev-ref HEAD)"
    echo "fecha:  $(date -Iseconds)"
    echo "autor:  $USER"
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "aviso:  compilado con cambios sin commit"
    fi
} > "$PREFIX/COMMIT"

if [ ! -x "$PREFIX/bin/commander3" ]; then
    echo "ERROR: no se ha generado $PREFIX/bin/commander3" >&2
    exit 1
fi
if ldd "$PREFIX/bin/commander3" | grep -q "not found"; then
    echo "AVISO: faltan librerías:" >&2
    ldd "$PREFIX/bin/commander3" | grep "not found" >&2
fi

echo
echo "Commander3 instalado en $PREFIX"
echo "Logs en $BUILD (se puede borrar)."