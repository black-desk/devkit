# External integration scope

Yazi retains its default binary features, but its default scripts call external
programs. Forge's optional groups cover file, ffmpeg, imagemagick, poppler,
resvg, 7zip, jq, chafa, fzf, zoxide, xclip/xsel, mediainfo and exiftool, in
addition to Git/fd/ripgrep. These are opt-in dependencies on forge, not all
installed by a plain yazi install. Making the same groups available in our
channel requires an explicit expansion of the ordinary package inventory; none
is silently added by this audit.

The comparison used
[conda-forge Yazi](https://github.com/conda-forge/yazi-feedstock/tree/ceae4efb5ef5a88dd0e3ed3ba87fe79e64c4be04/recipe).
Adding these helper groups is a scope decision, not an approved expansion from
the feature audit.
