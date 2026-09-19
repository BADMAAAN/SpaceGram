# SpaceGram icon masters

The current masters are `SpaceGram-Primary.png` and `SpaceGram-Alternate.png`.
Both are 1254 x 1254 opaque RGB squares. The space scene reaches every edge;
there is no rounded container, outer margin, bevel or baked corner mask.
iOS applies the final app-icon mask. Original framed JPEGs are preserved under
`../LegacySources/` and are not packaged by the app.

Rebuild with `python tools/generate_spacegram_icons.py` (Pillow required).
The generator uses the existing catalog manifests to export 34 RGB/sRGB PNG
renditions and the 444 x 444 `Telegram/Telegram-iOS/Resources/SpaceGramWelcome.png`.
Existing primary/alternate names, plist keys, sizes and switching behavior stay
intact. The alternate generated alpha was flattened onto black for opaque iOS
export; neither catalog has transparency. No source is fetched at build time.

The masters were edited using the built-in imagegen tool on 2026-09-19.

## Primary edit prompt

Edit target: attached SpaceGram PRIMARY icon. Precise-object-edit for production iOS app icon, square 1024x1024 opaque full-bleed artwork. Remove the baked-in rounded-square tile, bevel, container edge, outer black margin and surrounding shadow completely. Extend the existing space background naturally to ALL four straight canvas edges and all four corners. Preserve the exact silver ribbon letter S design, its proportions, subtle dark orbit with star, graphite monochrome palette and planet horizon. Slightly enlarge the existing composition to occupy the canvas sensibly, S about 66 percent canvas height, all parts of S and orbit star visible. Background must be one continuous space scene across the entire square; NO rounded rectangle outlines, NO inset square, NO frame, NO icon mockup, NO corner radius. iOS will apply its own mask. Preserve the softer low-contrast PRIMARY look as distinguished from the alternate. Output only one corrected master artwork.

## Alternate edit prompt

Edit target: attached SpaceGram ALTERNATE icon. Precise-object-edit for production iOS app icon. Opaque square 1024x1024 full-bleed artwork. Remove the baked-in rounded-square tile, bevel, container edge, outer black margin and surrounding shadow completely. Extend the existing space background naturally to ALL four straight canvas edges and all corners. Preserve this alternate's exact bright silver ribbon S silhouette, bright diagonal orbital ring in front of the S with star in upper right, dramatic planet horizon and graphite monochrome palette. Slightly enlarge the composition so S is about 66 percent of the canvas height, all S parts and orbital star visible. Background must be one continuous space scene across entire square. NO rounded rectangle outlines, NO inset square, NO frame, NO icon mockup, NO corner radius. iOS applies the corner mask. Maintain alternate's brighter silver and orbit highlights. Output only one corrected master artwork.
