# Test plan: LinShare

LinShare is a network client: it talks to a MUSCLE server (BeShare protocol) and, for
downloads, directly to other LinShare/BeShare clients. The test runs two instances on one
display against a local server, so nothing reaches the public BeShare servers.

## Fixtures

**muscled**, MUSCLE's own server, built from `source/muscle/server` on the host:

    cp -r source/muscle $SCRATCH/muscle && cd $SCRATCH/muscle/server
    sed -i 's/^muscled : $(OBJFILES) $(ZLIBOBJS)/& MemoryAllocator.o/' Makefile
    make muscled CXXFLAGS="-std=gnu++17 -I.. -DMUSCLE_SINGLE_THREAD_ONLY \
      -DMUSCLE_ENABLE_ZLIB_ENCODING -DMUSCLE_AVOID_IPV6 -DMUSCLE_64_BIT_PLATFORM \
      -I../zlib/zlib" CFLAGS="-DZ_HAVE_UNISTD_H"
    ./muscled listen=127.0.0.1:2960 displaylevel=info > dist/V/evidence/{p}-fixture.log 2>&1 &

(The bundled Makefile leaves out MemoryAllocator.o, and muscled.cpp uses `requires` as a
name, hence C++17.) Check it answers: `ss -ltn | grep 2960`.

Each instance gets its own throwaway HOME and is started with the server address as its
argument: `HOME=$SCRATCH/hA <AppImage> 127.0.0.1` (A), then `HOME=$SCRATCH/hB ...` (B).
Under Xvfb the address is 127.0.0.1. Start them by hand (xtest.sh's `start` kills every
LinShare process).

## Fresh state

Linux: delete both throwaway HOMEs. Settings live in `~/.config/cosmoe/linshare_settings`,
data in `~/LinShare/{shared,downloads,logs}`. Before starting A, create
`$SCRATCH/hA/LinShare/shared/hello-from-{p}.txt` containing "hello from {p}".

## Feature checks

### query
Steps: in B's window, triple-click the query text field (right of the "Query:" menu; it
holds "*.hpkg" on a first run), type "hello*", click "Start Query". Enlarge B's window if
the results list shows less than one row.
PASS when: OCR of B's window, saved as {p}-query.txt, shows "hello-from-{p}.txt" (the file
name alone, not A's path).

### download
Steps: click the "hello-from-{p}.txt" row, click "Download Selected Files". Wait for the
transfer list to say "Download complete".
PASS when: `$SCRATCH/hB/LinShare/downloads/hello-from-{p}.txt` exists and its sha256 equals
the shared file's. Only then write `sha256 match hello-from-{p}.txt` to {p}-download.txt.

### chat
Steps: click B's "Chat:" field, type "chat from {p} B", press Return. Bring A's window to
the front.
PASS when: OCR of A's window, saved as {p}-chat.txt, shows "chat from {p} B".

Also look at, without a gate check: a file added to A's shared folder while it runs turns
up in B's next query (node monitoring); double-clicking B's finished download calls
xdg-open with its path (xtest.sh's fake xdg-open log).
