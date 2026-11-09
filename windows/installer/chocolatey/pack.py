# Pack the Chocolatey package without choco (Docker choco crashes under arm emulation):
#   python3 -I windows/installer/chocolatey/pack.py windows/installer/chocolatey/viettelex out/viettelex.X.Y.Z.nupkg
# OPC parts must use NuGet paths ([Content_Types].xml, _rels/.rels,
# package/services/metadata/core-properties/*.psmdcp) or the Chocolatey validator flags them as package files.

import sys, os, zipfile, uuid, re
pkg, out = sys.argv[1], sys.argv[2]
nuspec = open(os.path.join(pkg,'viettelex.nuspec'),encoding='utf-8').read()
idv = re.search(r'<id>([^<]+)</id>',nuspec).group(1)
files=[]
for root,_,fs in os.walk(pkg):
    for f in fs:
        if f.endswith('.nupkg') or f.startswith('.'): continue
        p=os.path.join(root,f); files.append((p, os.path.relpath(p,pkg).replace(os.sep,'/')))
ct='<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" /><Default Extension="nuspec" ContentType="application/octet" /><Default Extension="ps1" ContentType="application/octet" /><Default Extension="psmdcp" ContentType="application/vnd.openxmlformats-package.core-properties+xml" /><Default Extension="txt" ContentType="application/octet" /><Default Extension="md" ContentType="application/octet" /></Types>'
cp='package/services/metadata/core-properties/'+uuid.uuid4().hex+'.psmdcp'
rels=f'<?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/viettelex.nuspec" Id="R{uuid.uuid4().hex[:16]}" /><Relationship Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="/{cp}" Id="R{uuid.uuid4().hex[:16]}" /></Relationships>'
ver=re.search(r'<version>([^<]+)</version>',nuspec).group(1)
core=f'<?xml version="1.0" encoding="utf-8"?><coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"><dc:creator>VietTelex</dc:creator><dc:identifier>{idv}</dc:identifier><version>{ver}</version><lastModifiedBy>pack.py</lastModifiedBy></coreProperties>'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml',ct); z.writestr('_rels/.rels',rels); z.writestr(cp,core)
    for p,a in files: z.write(p,a)
print(out, [a for _,a in files])
