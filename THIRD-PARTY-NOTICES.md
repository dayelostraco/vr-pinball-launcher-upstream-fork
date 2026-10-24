# Third-party notices

The project's MIT license covers original launcher source. Separate terms apply
to the components below. This fork preserves credit to the original author,
[keithbphillips](https://github.com/keithbphillips/vr-pinball-launcher).

| Component | Use / source | Notice |
|---|---|---|
| AutoOculusTouch, Kojack (rajetic), copyright 2017/2021 | Bundled AHK library and DLL for the optional Meta/Oculus bridge; [upstream](https://github.com/rajetic/auto_oculus_touch) declares MIT | [MIT text](licenses/AutoOculusTouch-MIT.txt), retained source headers and `ControllerBridge/auto_oculus_touch_README.txt` |
| vJoy, Shaul Eizikovich, copyright 2017 | `ControllerBridge/vJoyInterface.dll`, a dependency of the optional bridge; [upstream license](https://github.com/shauleiz/vJoy/blob/master/LICENSE.txt) | [MIT text](licenses/vJoy-MIT.txt). The bundled DLL matches the upstream AutoOculusTouch repository blob `8c67ef5bd77c1bf7078c45178dc2128406b9fc21`. No vJoy driver is installed by this project. |
| Liberation Sans | TextMesh Pro default font | [SIL Open Font License](licenses/LiberationSans-OFL.txt) |
| Unity engine and Unity packages | Built with Unity 6000.6.2f1; exact package versions are in `Packages/packages-lock.json` | Unity's own terms apply to its engine and packages. Package license/third-party notices from this release's resolved dependencies are retained under [licenses/unity](licenses/unity). These include OpenXR/Khronos and TextMesh Pro notices. |

AutoOculusTouch uses the Oculus SDK/runtime. Its upstream MIT declaration does
not relicense Meta's runtime or SDK; those retain their own terms. The runtime is
installed separately by the user. AutoHotkey, VPX, VPinMAME, FlexDMD and other
optional downloads also retain their own licenses; this project's MIT license
does not cover them. See their upstream distributions for notices and source.

Tables, ROMs, PuP packs, community artwork and preview videos are not included in
the installer or source release. Public demonstration images/video use a
synthetic library with original procedural artwork from `ReleasePreview.cs`. Media tools
can fetch third-party artwork at the user's request; authors retain their rights.

When updating bundled libraries or Unity packages, update these notices and
retain the corresponding upstream license text before publishing a release.
