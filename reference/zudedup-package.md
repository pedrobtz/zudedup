# zudedup: Content-Defined Chunking and Content-Addressed Storage

Split byte streams into variable-size chunks at boundaries chosen by
their content, with the 'FastCDC' algorithm and normalised chunking, so
that two versions of a large object which differ in a few places share
almost every chunk. Each chunk is hashed with 'XXH3-128' (fast, not
cryptographic) or 'SHA-256'; the ordered hashes form a manifest, a
strong identity for the whole object that can be compared with another.
A small content-addressed store keeps each chunk once, in a directory or
behind any backend written as a few R functions.

## See also

Useful links:

- <https://pedrobtz.github.io/zudedup/>

- <https://github.com/pedrobtz/zudedup>

- Report bugs at <https://github.com/pedrobtz/zudedup/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]
