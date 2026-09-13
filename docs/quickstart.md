# Quickstart

Replace something in the buffer you are in, and look at the hits before
committing to any of them:

```vim
:Replace foo bar
```

Then the wider cases:

```vim
:Replace foo bar cwd --dry     " stats and a diff over the working directory, no writes
:Replace foo bar cwd --all     " apply everywhere, no picker
:'<,'>Replace foo bar          " only within the visual selection
:Surround word **              " **word** — wrap every match with a delimiter
```

`<Tab>` completes at every slot of the command: the scope keywords, all 41 flag
names at a bare `--`, and the values of the four flags that have any.

Verify your setup any time with:

```vim
:checkhealth replacer
```

See [what-you-get.md](what-you-get.md) for the picker keymaps, or
[commands.md](commands.md) for the full flag reference.
