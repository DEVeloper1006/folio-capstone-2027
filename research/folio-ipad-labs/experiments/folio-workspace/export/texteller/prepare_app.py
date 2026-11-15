"""Stage exported models/fixtures and create the standalone iOS probe project."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import shutil

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "results/on-device-texteller")
    parser.add_argument("--precision", choices=["fp16", "fp32"], default="fp16")
    parser.add_argument("--team")
    args = parser.parse_args()
    app = HERE / "ProbeApp"
    generated = app / "Generated"
    fixtures = generated / "Fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    reference = json.loads((args.output / "reference.json").read_text())
    for name in ["Encoder", "Decoder"]:
        source = (args.output / "models" / args.precision / f"{name}.mlpackage").resolve()
        if not source.exists():
            raise SystemExit(f"Export {source} first")
        target = generated / f"{name}.mlpackage"
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            raise SystemExit(f"Refusing to replace non-symlink {target}")
        target.symlink_to(source, target_is_directory=True)
    rows = []
    for row in reference["fixtures"]:
        for name in [row["image"], row["tensor"]]:
            shutil.copy2(args.output / "fixtures" / name, fixtures / name)
        rows.append({"id": row["id"], "image": row["image"], "tensor": row["tensor"],
                     "groundTruth": row["ground_truth"], "referenceLatex": row["latex"], "tokens": row["tokens"]})
    shutil.copy2(args.output / "fixtures/tokenizer-table.json", fixtures / "tokenizer-table.json")
    math_assets = REPO.parent / "ink-pad/inkpad/inkpad/Resources"
    for name in ["tex-svg.js", "LICENSE-MathJax.txt"]:
        if not (math_assets / name).exists():
            raise SystemExit(f"Missing existing bundled MathJax asset: {math_assets / name}")
        shutil.copy2(math_assets / name, fixtures / name)
    shutil.copy2(app / "preview.html", fixtures / "preview.html")
    (fixtures / "probe-manifest.json").write_text(json.dumps({"revision": reference["revision"],
        "adapter": reference["adapter"], "fixtures": rows}, indent=2))
    team = args.team
    if not team:
        existing = REPO.parent / "ink-pad/inkpad/inkpad.xcodeproj/project.pbxproj"
        match = re.search(r"DEVELOPMENT_TEAM = ([A-Z0-9]+);", existing.read_text()) if existing.exists() else None
        team = match.group(1) if match else ""
    project = app / "TextellerProbe.xcodeproj"
    project.mkdir(exist_ok=True)
    (project / "project.pbxproj").write_text(PROJECT.replace("__TEAM__", team))
    print("Prepared", project)
    print("Models:", args.precision, "; fixtures are synthetic, with normalized tensors")


PROJECT = '''// !$*UTF8*$!
{
 archiveVersion = 1; classes = {}; objectVersion = 56;
 objects = {
 A00000000000000000000001 = {isa = PBXProject; attributes = {LastUpgradeCheck = 2620;}; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = A00000000000000000000003; productRefGroup = A00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000005);};
 A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000006, A00000000000000000000007); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000008, A00000000000000000000023, A00000000000000000000024, A00000000000000000000009, A00000000000000000000010, A00000000000000000000011, A00000000000000000000004); sourceTree = "<group>";};
 A00000000000000000000004 = {isa = PBXGroup; children = (A00000000000000000000012); name = Products; sourceTree = "<group>";};
 A00000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = A00000000000000000000013; buildPhases = (A00000000000000000000014, A00000000000000000000015, A00000000000000000000016); buildRules = (); dependencies = (); name = TextellerProbe; productName = TextellerProbe; productReference = A00000000000000000000012; productType = "com.apple.product-type.application";};
 A00000000000000000000006 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-Onone";};};
 A00000000000000000000007 = {isa = XCBuildConfiguration; name = Release; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O";};};
 A00000000000000000000008 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProbeApp.swift; sourceTree = "<group>";};
 A00000000000000000000009 = {isa = PBXFileReference; lastKnownFileType = folder.mlpackage; path = Generated/Encoder.mlpackage; sourceTree = "<group>";};
 A00000000000000000000010 = {isa = PBXFileReference; lastKnownFileType = folder.mlpackage; path = Generated/Decoder.mlpackage; sourceTree = "<group>";};
 A00000000000000000000011 = {isa = PBXFileReference; lastKnownFileType = folder; path = Generated/Fixtures; sourceTree = "<group>";};
 A00000000000000000000012 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TextellerProbe.app; sourceTree = BUILT_PRODUCTS_DIR;};
 A00000000000000000000013 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000017, A00000000000000000000018); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
 A00000000000000000000014 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000019, A00000000000000000000025, A00000000000000000000026, A00000000000000000000020, A00000000000000000000021); runOnlyForDeploymentPostprocessing = 0;};
 A00000000000000000000015 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
 A00000000000000000000016 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (A00000000000000000000022); runOnlyForDeploymentPostprocessing = 0;};
 A00000000000000000000017 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = __TEAM__; PRODUCT_BUNDLE_IDENTIFIER = com.dev.inkpad.textellerprobe; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = "2"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UIFileSharingEnabled = YES; INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_CFBundleDisplayName = "Folio ML Probe"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; SWIFT_EMIT_LOC_STRINGS = YES;};};
 A00000000000000000000018 = {isa = XCBuildConfiguration; name = Release; buildSettings = {CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = __TEAM__; PRODUCT_BUNDLE_IDENTIFIER = com.dev.inkpad.textellerprobe; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = "2"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UIFileSharingEnabled = YES; INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_CFBundleDisplayName = "Folio ML Probe"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES;};};
 A00000000000000000000019 = {isa = PBXBuildFile; fileRef = A00000000000000000000008;};
 A00000000000000000000020 = {isa = PBXBuildFile; fileRef = A00000000000000000000009;};
 A00000000000000000000021 = {isa = PBXBuildFile; fileRef = A00000000000000000000010;};
 A00000000000000000000022 = {isa = PBXBuildFile; fileRef = A00000000000000000000011;};
 A00000000000000000000023 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ImagePreprocessor.swift; sourceTree = "<group>";};
 A00000000000000000000024 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PencilRecognition.swift; sourceTree = "<group>";};
 A00000000000000000000025 = {isa = PBXBuildFile; fileRef = A00000000000000000000023;};
 A00000000000000000000026 = {isa = PBXBuildFile; fileRef = A00000000000000000000024;};
 };
 rootObject = A00000000000000000000001;
}
'''


if __name__ == "__main__":
    main()
