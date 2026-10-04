# Emptying a cargo ship (v1.3f)
To make the "empty" Bulk Freighter: in the cargo span (z -0.145..0.175 of the oriented full model) triangles outside
the spine (|x| > 0.024) whose texture is bright (above the 45th percentile there) are the crates and are removed; the
dark ones are the frame and stay. Then loose crumbs under 40 triangles are dropped. See the session notes in DESIGN §22.
