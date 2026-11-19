from pathlib import Path
from uuid import uuid5, NAMESPACE_DNS
import json, math, struct, zlib

root = Path(__file__).resolve().parent
sources = sorted((root / "Think/Sources").glob("*.swift"))
project_dir = root / "Think.xcodeproj"
project_dir.mkdir(exist_ok=True)

# Draw a clean 1024px app icon entirely with Python's standard library.
# This avoids external dependencies in the GitHub macOS runner.
asset = root / "Think/Assets.xcassets/AppIcon.appiconset"
asset.mkdir(parents=True, exist_ok=True)
(asset / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "ThinkIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}))
# The icon recreates the irregular Think head outline from the brand mark.
# It is rasterized from sampled cubic curves, not from a generic circle.
side = 1024
pixels = bytearray(bytes((255, 255, 254)) * (side * side))
purple = (169, 69, 227)
graphite = (42, 41, 47)

# Four-tip star with a compact curved diamond center.
for y in range(318, 626):
    dy = (y - 470) / 135.0
    for x in range(359, 673):
        dx = (x - 516) / 135.0
        radius = math.hypot(dx, dy)
        angle = math.atan2(dy, dx)
        limit = 0.20 + 0.40 * abs(math.cos(2 * angle)) ** 9
        if radius < limit:
            p = (y * side + x) * 3
            pixels[p:p+3] = bytes(purple)

def convert(point):
    return (178 + 17.6 * point[0], 175 + 17.6 * point[1])

def sample_cubic(a, b, c, d, steps=42):
    points = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        points.append((
            u**3*a[0] + 3*u*u*t*b[0] + 3*u*t*t*c[0] + t**3*d[0],
            u**3*a[1] + 3*u*u*t*b[1] + 3*u*t*t*c[1] + t**3*d[1]
        ))
    return points

outline = []
outline += sample_cubic((5,23),(3,11),(9,3),(16,3))
outline += sample_cubic((16,3),(27,0),(34,6),(32,15))[1:]
outline += sample_cubic((32,15),(34,21),(30,26),(23,29))[1:]
outline += [(24,35),(16,35),(15,28)]
outline += sample_cubic((15,28),(7,27),(6,27),(5,23))[1:]
outline = [convert(p) for p in outline]

# Draw softly anti-aliased charcoal outline by distance to path segments.
stroke = 13.5
for (x1,y1),(x2,y2) in zip(outline[:-1],outline[1:]):
    vx, vy = x2-x1, y2-y1
    length2 = max(1e-8, vx*vx + vy*vy)
    left = max(0, int(min(x1,x2) - stroke))
    right = min(side, int(max(x1,x2) + stroke) + 1)
    top = max(0, int(min(y1,y2) - stroke))
    bottom = min(side, int(max(y1,y2) + stroke) + 1)
    for y in range(top,bottom):
        for x in range(left,right):
            wx, wy = x+0.5-x1, y+0.5-y1
            t = max(0.0, min(1.0, (wx*vx+wy*vy)/length2))
            dist = math.hypot(wx-t*vx, wy-t*vy)
            alpha = max(0.0, min(1.0, (stroke/2 + 0.7 - dist)))
            if alpha > 0:
                p = (y*side+x)*3
                for j in range(3):
                    current = pixels[p+j]
                    pixels[p+j] = int(current*(1-alpha) + graphite[j]*alpha)

raw = zlib.compress(
    b"".join(b"\x00" + pixels[y*side*3:(y+1)*side*3] for y in range(side)),
    9
)

def png_chunk(tag, data):
    return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)
(asset / "ThinkIcon.png").write_bytes(
    b"\x89PNG\r\n\x1a\n" +
    png_chunk(b"IHDR", struct.pack("!2I5B", 1024, 1024, 8, 2, 0, 0, 0)) +
    png_chunk(b"IDAT", raw) + png_chunk(b"IEND", b"")
)
(root / "Think/Assets.xcassets/Contents.json").write_text(json.dumps({"info":{"author":"xcode","version":1}}))

keys = {}
def id(key):
    if key not in keys:
        keys[key] = uuid5(NAMESPACE_DNS, "think-build-2026-" + key).hex[:24].upper()
    return keys[key]

def ref_list(names):
    return "(\n" + "".join("\t\t\t\t" + id(k) + " /* " + k + " */,\n" for k in names) + "\t\t\t)"

objects=[]
def add(key, isa, body):
    objects.append("\t\t" + id(key) + " /* " + key + " */ = {\n\t\t\tisa = " + isa + ";\n" + body + "\t\t};")

for file in sources:
    n = file.name
    add("file_"+n, "PBXFileReference", f'\t\t\tlastKnownFileType = sourcecode.swift; path = {n}; sourceTree = "<group>";\n')
    add("build_"+n, "PBXBuildFile", f'\t\t\tfileRef = {id("file_"+n)} /* {n} */;\n')
add("assets", "PBXFileReference", '\t\t\tlastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";\n')
add("assets-build", "PBXBuildFile", f'\t\t\tfileRef = {id("assets")} /* assets */;\n')
add("app", "PBXFileReference", '\t\t\texplicitFileType = wrapper.application; includeInIndex = 0; path = Think.app; sourceTree = BUILT_PRODUCTS_DIR;\n')
add("root-group", "PBXGroup", f'\t\t\tchildren = {ref_list(["think-group","products-group"])};\n\t\t\tsourceTree = "<group>";\n')
add("products-group", "PBXGroup", f'\t\t\tchildren = {ref_list(["app"])};\n\t\t\tname = Products; sourceTree = "<group>";\n')
add("think-group", "PBXGroup", f'\t\t\tchildren = {ref_list(["sources-group","assets"])};\n\t\t\tpath = Think; sourceTree = "<group>";\n')
add("sources-group", "PBXGroup", f'\t\t\tchildren = {ref_list(["file_"+f.name for f in sources])};\n\t\t\tpath = Sources; sourceTree = "<group>";\n')
add("sources-phase", "PBXSourcesBuildPhase", f'\t\t\tbuildActionMask = 2147483647; files = {ref_list(["build_"+f.name for f in sources])};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n')
add("assets-phase", "PBXResourcesBuildPhase", f'\t\t\tbuildActionMask = 2147483647; files = {ref_list(["assets-build"])};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n')
add("frameworks-phase", "PBXFrameworksBuildPhase", '\t\t\tbuildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;\n')
add("target", "PBXNativeTarget", f'\t\t\tbuildConfigurationList = {id("target-configs")};\n\t\t\tbuildPhases = {ref_list(["sources-phase","frameworks-phase","assets-phase"])};\n\t\t\tbuildRules = (); dependencies = (); name = Think;\n\t\t\tproductName = Think;\n\t\t\tproductReference = {id("app")} /* Think.app */;\n\t\t\tproductType = "com.apple.product-type.application";\n')
add("project", "PBXProject", f'\t\t\tattributes = {{ LastUpgradeCheck = 1600; }};\n\t\t\tbuildConfigurationList = {id("project-configs")};\n\t\t\tcompatibilityVersion = "Xcode 14.0";\n\t\t\tdevelopmentRegion = ru;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (ru, en, Base);\n\t\t\tmainGroup = {id("root-group")};\n\t\t\tproductRefGroup = {id("products-group")};\n\t\t\tprojectDirPath = ""; projectRoot = "";\n\t\t\ttargets = {ref_list(["target"])};\n')
base = {
    "ALWAYS_SEARCH_USER_PATHS":"NO",
    "CLANG_ENABLE_MODULES":"YES",
    "CLANG_ENABLE_OBJC_ARC":"YES",
    "CODE_SIGN_STYLE":"Automatic",
    "IPHONEOS_DEPLOYMENT_TARGET":"17.0",
    "SDKROOT":"iphoneos",
    "SWIFT_VERSION":"5.0",
    "TARGETED_DEVICE_FAMILY":'"1,2"'
}
target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon",
    "CODE_SIGN_STYLE":"Automatic",
    "CURRENT_PROJECT_VERSION":"6",
    "GENERATE_INFOPLIST_FILE":"YES",
    "INFOPLIST_KEY_CFBundleDisplayName":"Think",
    "INFOPLIST_KEY_LSApplicationCategoryType":'"public.app-category.productivity"',
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation":"YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents":"YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation":"YES",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription":'"Think использует микрофон для записи идей голосом."',
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription":'"Think превращает твою речь в текст идеи."',
    "IPHONEOS_DEPLOYMENT_TARGET":"17.0",
    "MARKETING_VERSION":"1.5",
    "PRODUCT_BUNDLE_IDENTIFIER":"com.think.ideas.personal",
    "PRODUCT_NAME":'"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS":'"iphoneos iphonesimulator"',
    "SWIFT_EMIT_LOC_STRINGS":"YES",
    "SWIFT_VERSION":"5.0",
    "TARGETED_DEVICE_FAMILY":'"1,2"'
}
for prefix, settings in (("project", base), ("target",target)):
    for config in ("Debug", "Release"):
        lines = "".join("\t\t\t\t" + k + " = " + v + ";\n" for k,v in settings.items())
        lines += '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = ' + ('"-Onone"' if config == "Debug" else '"-O"') + ';\n'
        add(prefix + "-" + config, "XCBuildConfiguration", f'\t\t\tbuildSettings = {{\n{lines}\t\t\t}};\n\t\t\tname = {config};\n')
for prefix in ("project","target"):
    add(prefix+"-configs","XCConfigurationList",f'\t\t\tbuildConfigurations = {ref_list([prefix+"-Debug",prefix+"-Release"])};\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n')
content = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + '\n\t};\n\trootObject = ' + id("project") + ' /* Project */;\n}\n'
(project_dir / "project.pbxproj").write_text(content)
print("Generated Xcode project; Swift files:", len(sources))

scheme_path = project_dir / "xcshareddata/xcschemes/Think.xcscheme"
if scheme_path.exists():
    scheme_path.write_text(scheme_path.read_text().replace("TEMP_TARGET_ID", id("target")))
