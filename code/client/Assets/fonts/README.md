Menu typography uses DynaPuff for playful headings and Nunito at weight 600 for
rounded, readable body text. Both families are bundled under the SIL Open Font
License; the adjacent OFL files contain their copyright notices and licenses.

Official sources:
- https://github.com/google/fonts/tree/main/ofl/dynapuff
- https://github.com/google/fonts/tree/main/ofl/nunito

The `.res` files embed the complete fonts so packaged games need no installed
fonts or runtime access to source TTF files. Original TTFs live in `sources/`.
To rebuild, run `tools/build_ui_fonts.gd` with Godot as described in that file.
