# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=meson-python
PYTHON_COMPAT=( python3_{10..12} pypy3 )
PYTHON_REQ_USE="threads(+)"
FORTRAN_NEEDED=lapack

inherit distutils-r1 flag-o-matic fortran-2 multiprocessing pypi toolchain-funcs

DESCRIPTION="Fast array and numerical python library"
HOMEPAGE="
	https://numpy.org/
	https://github.com/numpy/numpy/
	https://pypi.org/project/numpy/
"
SRC_URI+=" https://dev.gentoo.org/~sam/distfiles/${CATEGORY}/${PN}/${PN}-1.25.2-patches.tar.xz"

LICENSE="BSD"
SLOT="0"
IUSE="lapack"
if [[ ${PV} != *_rc* ]] ; then
	KEYWORDS="amd64 arm arm64 hppa ~ia64 ~loong ~m68k ppc ppc64 ~riscv ~s390 sparc x86"
fi

RDEPEND="
	lapack? (
		>=virtual/cblas-3.8
		>=virtual/lapack-3.8
	)
"
BDEPEND="
	${RDEPEND}
	>=dev-util/meson-1.1.0
	>=dev-python/cython-0.29.30[${PYTHON_USEDEP}]
	lapack? (
		virtual/pkgconfig
	)
	test? (
		$(python_gen_cond_dep '
			>=dev-python/cffi-1.14.0[${PYTHON_USEDEP}]
		' 'python*')
		dev-python/charset-normalizer[${PYTHON_USEDEP}]
		>=dev-python/hypothesis-5.8.0[${PYTHON_USEDEP}]
		dev-python/pytest-xdist[${PYTHON_USEDEP}]
		>=dev-python/pytz-2019.3[${PYTHON_USEDEP}]
	)
"

PATCHES=(
	"${WORKDIR}"/${PN}-1.25.2-patches
)

distutils_enable_tests pytest

python_prepare_all() {
	append-flags -fno-strict-aliasing

	distutils-r1_python_prepare_all

	# TODO: Please drop once 1.25.2-meson-pyproject.toml.patch is gone
	sed -i -e "s:version = \"2.0.0.dev0\":version = \"${PV}\":" pyproject.toml || die
}

python_configure_all() {
	DISTUTILS_ARGS=(
		-Dblas=$(usev lapack cblas)
		-Dlapack=$(usev lapack lapack)
	)
}

python_test() {
	local EPYTEST_DESELECT=(
		# Very disk-and-memory-hungry
		lib/tests/test_io.py::TestSaveTxt::test_large_zip
		lib/tests/test_io.py::TestSavezLoad::test_closing_fid
		lib/tests/test_io.py::TestSavezLoad::test_closing_zipfile_after_load

		# Precision problems
		core/tests/test_umath_accuracy.py::TestAccuracy::test_validate_transcendentals

		# Runs the whole test suite recursively, that's just crazy
		core/tests/test_mem_policy.py::test_new_policy

		# XXX: I've no idea why this ends up being needed in deselect and not ignore
		typing/tests/test_typing.py
		# Uses huge amount of memory
		core/tests/test_mem_overlap.py
	)

	if [[ ${EPYTHON} == python3.12 ]]; then
		EPYTEST_DESELECT+=(
			typing/tests/test_isfile.py::TestIsFile::test_isfile
			tests/test_public_api.py::test_all_modules_are_expected_2
			tests/test_public_api.py::test_api_importable

			random/tests/test_extending.py
			tests/test_ctypeslib.py
		)

		EPYTEST_IGNORE+=(
			random/tests/test_extending.py
			tests/test_ctypeslib.py
		)
	fi

	if [[ ${EPYTHON} == pypy3 ]]; then
		EPYTEST_DESELECT+=(
			# TODO: crashed
			lib/tests/test_histograms.py::TestHistogram::test_big_arrays
		)
	fi

	if use arm && [[ $(uname -m || echo "unknown") == "armv8l" ]] ; then
		# Degenerate case of arm32 chroot on arm64, bug #774108
		EPYTEST_DESELECT+=(
			core/tests/test_cpu_features.py::Test_ARM_Features::test_features
		)
	fi

	if use x86 ; then
		EPYTEST_DESELECT+=(
			# https://github.com/numpy/numpy/issues/18388
			core/tests/test_umath.py::TestRemainder::test_float_remainder_overflow
			# https://github.com/numpy/numpy/issues/18387
			random/tests/test_generator_mt19937.py::TestRandomDist::test_pareto
			# more precision problems
			core/tests/test_einsum.py::TestEinsum::test_einsum_sums_int16
		)
	fi

	if use hppa ; then
		EPYTEST_DESELECT+=(
			# TODO: Get selectedrealkind updated!
			# bug #907228
			# https://github.com/numpy/numpy/issues/3424 (https://github.com/numpy/numpy/issues/3424#issuecomment-412369029)
			# https://github.com/numpy/numpy/pull/21785
			f2py/tests/test_kind.py::TestKind::test_real
			f2py/tests/test_kind.py::TestKind::test_quad_precision
		)
	fi

	if [[ $(tc-endian) == "big" ]] ; then
		# https://github.com/numpy/numpy/issues/11831 and bug #707116
		EPYTEST_DESELECT+=(
			'f2py/tests/test_return_character.py::TestFReturnCharacter::test_all_f77[s1]'
			'f2py/tests/test_return_character.py::TestFReturnCharacter::test_all_f90[t1]'
			'f2py/tests/test_return_character.py::TestFReturnCharacter::test_all_f90[s1]'
			'f2py/tests/test_return_character.py::TestFReturnCharacter::test_all_f77[t1]'
			f2py/tests/test_kind.py::TestKind::test_int
		)
	fi

	case "${ABI}" in
		alpha|arm|hppa|m68k|o32|ppc|s390|sh|sparc|x86)
			EPYTEST_DESELECT+=(
				# too large for 32-bit platforms
				core/tests/test_ufunc.py::TestUfunc::test_identityless_reduction_huge_array
				'core/tests/test_multiarray.py::TestDot::test_huge_vectordot[float64]'
				'core/tests/test_multiarray.py::TestDot::test_huge_vectordot[complex128]'
				lib/tests/test_histograms.py::TestHistogram::test_big_arrays
			)
			;;
		*)
			;;
	esac

	rm -rf numpy || die
	epytest -n "$(makeopts_jobs)" --pyargs numpy
}

python_install_all() {
	local DOCS=( LICENSE.txt README.md THANKS.txt )
	distutils-r1_python_install_all
}
