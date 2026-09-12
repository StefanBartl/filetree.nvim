# Around it

How filetree.nvim's scope relates to its closest siblings in the collection.

## fileops.nvim

[fileops.nvim](https://github.com/StefanBartl/fileops.nvim) — the same file
operations without a tree in front of them, from any buffer. It fires `User
FileopsChanged`, which this plugin's watcher picks up, so the two stay in
agreement without depending on each other.

## pdfport.nvim

[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) — the PDF bridge:
a `.pdf` node opens rendered in a buffer instead of shelling out to a system
reader.

## images.nvim

[images.nvim](https://github.com/StefanBartl/images.nvim) — the same idea for
image nodes in the preview pane.

## reposcope.nvim

[reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim) — clones a
repository; this is how you read it afterwards without leaving Neovim.

## Dependency shape

All of the above are soft: without them everything else works unchanged.
[lib.nvim](https://github.com/StefanBartl/lib.nvim) and one tree plugin are
the real dependencies — see [Requirements](installation.md#requirements).
