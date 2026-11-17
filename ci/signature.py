#!/usr/bin/env python3
"""Signature pour TestFlight sans Mac personnel.

  preparer : crée un certificat de distribution temporaire et un profil App Store
             pour l'app et le widget (via la clé API App Store Connect), installe le tout,
             et règle le projet en signature manuelle.
  nettoyer : supprime les profils et révoque le certificat temporaire.
             (Les builds déjà envoyées à TestFlight ne sont pas touchées.)
"""
import base64, json, os, subprocess, sys, time, uuid, urllib.request, urllib.error, re
import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
TMP = os.environ.get("RUNNER_TEMP", "/tmp")
ETAT = os.path.join(TMP, "signature.json")
BUNDLES = {"ca.tomtommusic.planif": "app", "ca.tomtommusic.planif.widget": "widget"}
GROUPE = "group.ca.tomtommusic.planif"


def jeton():
    with open(os.environ["KEY"]) as f:
        cle = f.read()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                      cle, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def api(methode, chemin, corps=None, essais=5):
    for n in range(essais):
        try:
            return _api(methode, chemin, corps)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            if e.code >= 500 and n < essais - 1:
                print(f"App Store Connect {methode} {chemin} -> {e.code}, nouvel essai dans {20 * (n + 1)} s")
                time.sleep(20 * (n + 1))
                continue
            print(f"::error::App Store Connect {methode} {chemin} -> {e.code} : {detail[:600]}")
            raise SystemExit(1)


def _api(methode, chemin, corps=None):
    req = urllib.request.Request(API + chemin, method=methode,
                                 data=json.dumps(corps).encode() if corps is not None else None,
                                 headers={"Authorization": "Bearer " + jeton(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        t = r.read()
        return json.loads(t) if t else {}


def sh(*cmd):
    subprocess.run(cmd, check=True)


def preparer():
    etat = {"profils": [], "certificat": None}
    existants = api("GET", "/certificates?limit=200").get("data", [])
    print("Certificats existants :", [(c["attributes"].get("certificateType"), c["attributes"].get("name"), c["attributes"].get("expirationDate", "")[:10]) for c in existants])
    # 1. Certificat de distribution temporaire
    cle = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = x509.CertificateSigningRequestBuilder().subject_name(
        x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Planif CI"), x509.NameAttribute(NameOID.COUNTRY_NAME, "CA")])
    ).sign(cle, hashes.SHA256())
    pem_csr = csr.public_bytes(serialization.Encoding.PEM).decode()
    r = api("POST", "/certificates", {"data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": pem_csr}}})
    cert_id = r["data"]["id"]
    etat["certificat"] = cert_id
    json.dump(etat, open(ETAT, "w"))
    der = base64.b64decode(r["data"]["attributes"]["certificateContent"])
    cert = x509.load_der_x509_certificate(der)
    open(f"{TMP}/cert.pem", "wb").write(cert.public_bytes(serialization.Encoding.PEM))
    open(f"{TMP}/key.pem", "wb").write(cle.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))
    from cryptography.hazmat.primitives.serialization import pkcs12
    chiffre = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
               .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1()).build(b"planif"))
    open(f"{TMP}/ci.p12", "wb").write(pkcs12.serialize_key_and_certificates(b"Planif CI", cle, cert, None, chiffre))
    kc = f"{TMP}/ci.keychain-db"
    sh("security", "create-keychain", "-p", "planif", kc)
    sh("security", "set-keychain-settings", "-lut", "21600", kc)
    sh("security", "unlock-keychain", "-p", "planif", kc)
    sh("security", "import", f"{TMP}/ci.p12", "-k", kc, "-P", "planif", "-A", "-f", "pkcs12")
    sh("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", "planif", kc)
    liste = subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True).stdout.split()
    sh("security", "list-keychains", "-d", "user", "-s", kc, *[x.strip('"') for x in liste])
    os.remove(f"{TMP}/key.pem")
    print("Certificat temporaire créé et installé.")

    # 2. Profils App Store (app et widget)
    noms = {}
    dossiers = [os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
                os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles")]
    for d in dossiers:
        os.makedirs(d, exist_ok=True)
    run = os.environ.get("GITHUB_RUN_NUMBER", "0")
    for ident in BUNDLES:
        b = api("GET", f"/bundleIds?filter[identifier]={ident}&limit=50")
        ids = [x["id"] for x in b["data"] if x["attributes"]["identifier"] == ident]
        if not ids:
            print(f"::error::L'App ID {ident} est introuvable dans le compte développeur.")
            raise SystemExit(1)
        nom = f"Planif CI {ident} {run}"
        p = api("POST", "/profiles", {"data": {"type": "profiles", "attributes": {"name": nom, "profileType": "IOS_APP_STORE"},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": ids[0]}},
                                   "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
        etat["profils"].append(p["data"]["id"])
        json.dump(etat, open(ETAT, "w"))
        contenu = base64.b64decode(p["data"]["attributes"]["profileContent"])
        u = p["data"]["attributes"].get("uuid") or str(uuid.uuid4())
        for d in dossiers:
            open(os.path.join(d, f"{u}.mobileprovision"), "wb").write(contenu)
        decode = subprocess.run(["security", "cms", "-D", "-i", os.path.join(dossiers[0], f"{u}.mobileprovision")], capture_output=True, text=True).stdout
        if GROUPE not in decode:
            print(f"::error::Le profil de {ident} ne contient pas le groupe {GROUPE}. Sur developer.apple.com, ouvre l'App ID {ident}, coche App Groups, clique Configure et coche {GROUPE}.")
            raise SystemExit(1)
        noms[ident] = nom
        print(f"Profil créé pour {ident} (avec le groupe d'apps).")

    # 3. Projet en signature manuelle, un profil par cible
    pbx = "Planif.xcodeproj/project.pbxproj"
    s = open(pbx).read()
    def regle(m):
        bloc = m.group(0)
        for ident, nom in noms.items():
            if re.search(r"PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(ident) + r";", bloc):
                bloc = bloc.replace("CODE_SIGN_STYLE = Automatic;",
                                    f'CODE_SIGN_STYLE = Manual;\n\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{nom}";')
                bloc = bloc.replace('DEVELOPMENT_TEAM = "";', f'DEVELOPMENT_TEAM = {os.environ["APPLE_TEAM_ID"]};')
        return bloc
    s = re.sub(r"buildSettings = \{.*?\n\t\t\t\};", regle, s, flags=re.S)
    open(pbx, "w").write(s)
    json.dump(noms, open(f"{TMP}/profils.json", "w"))
    print("Projet réglé en signature manuelle.")


def nettoyer():
    if not os.path.exists(ETAT):
        return
    etat = json.load(open(ETAT))
    for pid in etat.get("profils", []):
        try:
            api("DELETE", f"/profiles/{pid}")
        except SystemExit:
            pass
    if etat.get("certificat"):
        try:
            api("DELETE", f"/certificates/{etat['certificat']}")
            print("Certificat temporaire révoqué.")
        except SystemExit:
            pass


if __name__ == "__main__":
    {"preparer": preparer, "nettoyer": nettoyer}[sys.argv[1]]()
