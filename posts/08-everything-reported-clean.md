# Everything reported clean

This repo is the public version of a private one. The lab's real documentation carries addresses,
hostnames, account names and paths that have no business being published, so porting it meant
substituting all of that — and substitution is not a job to do by eye across two thousand lines.

So I wrote a checker. A list of patterns, run over every file, non-zero exit on a match, wired to
`pre-commit`.

It passed. It passed every single time I ran it.

It was also wrong in four separate ways, and every one of them was reporting clean the entire time
it was wrong. Which makes this the same post as [post 2](02-nothing-crashed.md), except the thing
quietly doing nothing was the thing whose only job was to catch things quietly doing nothing.

---

## `-I` is not ignore-case

```bash
grep -rInE "$pattern" .
```

`-I` means *ignore binary files*. Ignore-case is `-i`, lowercase. I had been reading that flag as
case-insensitivity for years, in a script where every pattern was written in lowercase.

So the check for family-relationship words — the ones that turn a technical writeup into something
about my household — passed for weeks with a capitalised one sitting in a document. It matched the
lowercase form. The document had a capital letter.

One capital letter, and a check that was structurally incapable of ever firing.

## A pattern grep rejected outright

The public-IP check is the one that actually matters. A residential address in a document is the
single value that points at a house, and everything else in the repo is comparatively harmless.

I'd written it with a negative lookahead to skip the private ranges:

```
\b(?!10\.|192\.168\.)([0-9]{1,3}\.){3}[0-9]{1,3}\b
```

`grep -E` has no lookarounds. It doesn't ignore them — it errors. The error went to stderr, which
the script was discarding, and an empty result set looks precisely like nothing matched.

The most important check in the file had been erroring on every run since the day I wrote it, and
printing `clean` each time.

The fix was to stop being clever: match every address, then filter the private ranges out with a
second `grep -v`. Uglier, and it works.

The general version is worth more than the specific one. **A check that can't tell "no matches" from
"didn't run" isn't a check.** Both look like success from the outside, and one of them is a lie.

## The escaped form

This is the one I would never have found by reading the code.

The port scripts are `sed` scripts. A `sed` script that replaces a real value necessarily contains
that value — that's what a substitution is. So the tooling built to strip identifying values out of
the docs was carrying a complete list of them.

Which I knew, and had decided was fine, because the checker was scanning everything.

It wasn't finding them. In a `sed` script the value appears escaped:

```
s/203\.0\.113\.7/<WAN-IP>/g
```

A pattern hunting for `203\.0\.113\.7` matches literal dots. It does not match a literal backslash
followed by a dot. The two forms don't see each other, and the escaped one is the form that lives in
every substitution map you'll ever write.

So the scan specifically looking for those values walked past all of them, in the one file
guaranteed to contain all of them, and reported clean. Then I committed it.

The fix had two halves. The maps moved out of the repo entirely — the scripts now take a map by
path and hold no values themselves. And the checker strips backslashes from each file before
matching, so the escaped form and the plain form collapse into the same thing.

The lesson generalizes further than I'd like: **anything that transforms private data into public
data contains all of it by definition.** Scrubbers, substitution maps, allowlists, test fixtures,
the golden files in your test suite. It's the last place anyone looks, because it reads as tooling
rather than content.

## The pattern that wasn't there

I found the fourth one the day before publishing, and not by running the checker. By reading.

There was no email pattern. Not a broken one — none at all. It had never occurred to me to write it.

My own address was sitting in a certbot example in the agent docs and on a line in a runbook, and
in both places it reads as entirely ordinary configuration. Nothing about `--email <EMAIL>` looks
like a leak. It looks like documentation.

It was also the commit author, which no amount of scanning file contents will ever reach.

The pattern took two minutes to add. The part that took longer was accepting what it implied: "the
checker passed" had quietly become the whole of my confidence, and the checker only knows the
things I already thought of. Every category it covers is a category I'd been burned by. The one I
hadn't been burned by yet was invisible.

---

## The working tree is not the history

All four of those are content bugs. There's a structural one underneath them.

The checker only ever saw current files. A value committed and later removed is gone from the
working tree and still sitting in the history — and the history is what goes public, in full, the
moment you flip the switch. Nobody has to dig for it. `git log -p` is right there.

That's how the deliberately weak sudo password from [post 6](06-the-agent-knew-more.md) ended up
somewhere it shouldn't have been. Not through the agent, not through the mechanism I'd built so
carefully. Through a commit.

There's no clever fix for this one. If a value ever entered the history, the history is the thing
that has to change — and it's much cheaper to do that while a repo is still private and nobody has
cloned it.

And then the part I nearly missed entirely: **the commit message is public too.** Mine described
this incident in detail, including a tidy list of exactly which categories of value had leaked and
where the substitution maps now lived. A summary of what's hidden and a pointer to where it's kept,
sitting permanently in `git log`, written by me, in the commit whose whole purpose was to establish
a clean history.

Scan the messages. Read them like a stranger would.

---

## Canary tests

Every check now gets tested in both directions before I trust it: a file containing a value it must
catch, and the clean tree it must not fire on.

That's the entire methodology and it would have caught three of the four immediately. The
case-sensitivity bug dies the first time you feed it a capitalised word. The broken lookahead dies
the first time you plant an address and watch the check print `clean` anyway. The escaped form dies
the moment you test against a real map file instead of a hand-written example.

**If I can't make a check fail on demand, I don't believe it when it passes.**

---

## If you're publishing a lab writeup

Everything I'd tell someone starting this, in order of how much it cost me:

- **Write a public repo. Never flip the private one.** Derived artifact, one direction, no exceptions.
- **Keep the substitution map outside the repo.** It contains every value you're removing.
- **Scan the history, not the working tree.** They are completely different questions.
- **Read your commit messages.** Yours are longer and more candid than you remember.
- **Canary every check in both directions.** A clean report from an untested check is worth nothing.
- **Then read the whole thing anyway, slowly.** The email was found by reading. No pattern I owned
  was ever going to catch it, because I hadn't thought of it — and that's exactly the category that
  matters.

The through-line of this entire series turned out to be the same sentence in a different costume:
the failures that cost the most are the ones that report success. Seven months of that on two
laptops, and then the tool I wrote to make sure I'd learned it did it to me one more time on the way
out the door.

---

*Back to the [series index](../README.md).*
