Use [Emacs](https://www.gnu.org/software/emacs/) to access protected folders on Android device using [SAF framework](https://developer.android.com/guide/topics/providers/document-provider). List their files in dedicated buffer, and click to open using [openwith](https://github.com/jpkotta/openwith).

## Rationale

Default folder isolation model in modern Android is great, but often times, it's difficult to access these folders from apps, especially from Termux environment. If you use Emacs on Termux, this package gives you good base to work with protected folders using SAF framework.

## Dependencies

- [f](https://github.com/rejeep/f.el)
- [openwith](https://github.com/jpkotta/openwith)
- [Termux](https://termux.dev/en/)

## Usage

1. request and grant access to protected folder using `termux-saf-managedir` in Termux terminal
2. in Emacs, call `termux-saf-browse` giving it folder URI from previous step as a parameter
3. view the content of protected folder, click on file name to open using openwith