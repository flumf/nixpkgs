{
  fetchurl,
  stdenvNoCC,
  version,
  ...
}:

let
  src = fetchurl {
    url = "mirror://openbsd/${version}/src.tar.gz";
    hash = "sha256-+zBcVTBZtI6O5kU585K3g8s4pnhlgj9vapTzsiChJos=";
  };

  sys = fetchurl {
    url = "mirror://openbsd/${version}/sys.tar.gz";
    hash = "sha256-ye8pQCHveq/V8Y/+jr/tYzlOWobWXXQ21tt4VR+dV/E=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "openbsd-src";
  inherit version;

  phases = [
    "unpackPhase"
    "patchPhase"
    "installPhase"
  ];

  unpackPhase = ''
    mkdir src/

    tar xvf ${src} -C src/
    tar xvf ${sys} -C src/
  '';

  installPhase = ''
    cp -r src/ $out/
  '';
}
