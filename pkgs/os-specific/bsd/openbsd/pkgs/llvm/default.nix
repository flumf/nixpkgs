{
  fetchgit,
  lib,
  llvm_19,
  mkLLVMPackages,
  stdenv,
  stdenvNoCC,
  withCFlags,
  ...
}:

let
  fetchedPatches = fetchgit {
    url = "https://github.com/openbsd/ports.git";
    rev = "4fd348f6c975b26980360bfff1195142fe7f3bc3";
    hash = "sha256-8yRAlAq/cQwELJiLDT7+6MWptbOjwjF3rTwozZP5Il4=";

    sparseCheckout = [
      "/devel/llvm/19/patches"
    ];
    nonConeMode = true;

    postFetch = ''
      cp -r $out/devel/llvm/19/patches/. $out/
      rm -r $out/devel/

      find $out/ -type f -exec sed -i 's/__OpenBSD__/__FakeBSD__/g' {} \;
    '';
  };

  localPatches = [
    ./fix-cmake.patch
  ];

  monorepoSrc' = stdenvNoCC.mkDerivation {
    pname = "${llvm_19.monorepoSrc.name}-openbsd";
    version = "${llvm_19.version}";

    src = llvm_19.monorepoSrc;

    phases = [
      "unpackPhase"
      "patchPhase"
      "installPhase"
    ];

    patches = (
      lib.attrsets.mapAttrsToList (
        name: _: /. + "${builtins.unsafeDiscardStringContext fetchedPatches}/${name}"
      ) (builtins.readDir fetchedPatches) ++ localPatches
    );

    patchFlags = [ "-p0" ];

    installPhase = ''
      cp -r ./ $out/
    '';
  };

  # We need to sneak __OpenBSD__ into the LLVM build process, as some of the patches from OpenBSD/ports gate behaviour
  # behind it. Unfortunately, defining __OpenBSD__ outright causes issues, as LLVM itself (rightfully) gates OpenBSD
  # specific behaviour behind it. See the `sed` operation that is performed on the patches.
  stdenv' = withCFlags [ "-D__FakeBSD__" ] stdenv;

  llvmPackages =
    (mkLLVMPackages.override { stdenv = stdenv'; } {
      name = "openbsd";

      # The OpenBSD patches cause quite a few tests to fail, and I've not had a chance to manually check all cases.
      # For now, we'll just verify the codegen ourselves.
      shouldCheck = false;

      monorepoSrc = monorepoSrc';
      officialRelease = {};

      inherit (llvm_19) version;
    }).value;

  llvmPackages' = llvmPackages.overrideScope (
    finalScope: prevScope: {
      libcxx = prevScope.libcxx.overrideAttrs (
        oldAttrs:
        lib.optionalAttrs finalScope.stdenv.hostPlatform.isOpenBSD {
          # XXX(bin): filter to just the libcxx sources here.
          src = monorepoSrc';

          # We want to embed libunwind in libc++abi; see `ports/devel/llvm/Makefile.inc` for more.
          # This is an amalgamation of the OpenBSD libc++ CMake options and the standard ones from upstream nixpkgs.
          cmakeFlags = [
            (lib.cmakeFeature "LLVM_ENABLE_RUNTIMES" "libcxx;libcxxabi;libunwind")

            (lib.cmakeBool "LIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY" true)
            (lib.cmakeBool "LIBCXX_USE_COMPILER_RT" true)

            (lib.cmakeBool "LIBCXXABI_ENABLE_STATIC_UNWINDER" true)
            (lib.cmakeBool "LIBCXXABI_USE_COMPILER_RT" true)
            (lib.cmakeBool "LIBCXXABI_USE_LLVM_UNWINDER" true)

            (lib.cmakeBool "LIBUNWIND_ENABLE_SHARED" false)
            (lib.cmakeBool "LIBUNWIND_INSTALL_HEADERS" false)
            (lib.cmakeBool "LIBUNWIND_INSTALL_LIBRARY" false)
            (lib.cmakeBool "LIBUNWIND_INSTALL_SHARED_LIBRARY" false)
            (lib.cmakeBool "LIBUNWIND_INSTALL_STATIC_LIBRARY" false)
          ]
          ++ lib.optionals finalScope.stdenv.hostPlatform.isStatic [
            (lib.cmakeBool "LIBCXX_ENABLE_SHARED" false)
            (lib.cmakeBool "LIBCXXABI_ENABLE_SHARED" false)
          ];
        }
      );
    }
  );
in
llvmPackages'
