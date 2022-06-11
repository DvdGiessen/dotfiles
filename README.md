# DvdGiessen's dotfiles

To set up on a new system:

```sh
git clone --bare git@github.com:DvdGiessen/dotfiles.git "$HOME/.dotgit/"
alias dotgit="$(which git)"' --git-dir="$HOME/.dotgit/" --work-tree="$HOME/"'
dotgit checkout
dotgit config status.showUntrackedFiles no
```

