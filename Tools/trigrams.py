#!/usr/bin/env python3
"""Regenerates Sources/LayoutSwitcher/Trigrams.swift. Run from the project root after downloading the lists,
which stay out of the repository (.gitignore):
  for l in ru en uk de …; do curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/$l/${l}_50k.txt; done
  python3 Tools/trigrams.py
Tables are keyed by the language macOS reports for a keyboard layout (kTISPropertyInputSourceLanguages); that is
the list's own code except where LANGS says "layout=list". Left out: languages with no keyboard layout in macOS
(they type on another one), input methods (ja, ko, zh), scripts without spaces or with combining marks (th, hi,
bn, ...) and the lists too short to trust (hy, kk, ur have 5-10k words, not 50k)."""
import collections, math, textwrap, unicodedata
LANGS = 'ar bg cs da de el en es et fa fi fr he hr hu is it ka lt lv mk nb=no nl pl pt ro ru sk sl sq sr-Latn=sr sv tr uk vi'
# Letters of a neighbour written in the same script: Ukrainian subtitles are 6% Russian lines.
FOREIGN = {'uk': 'ыэёъ'}

def read(lang, path):
    words = [(unicodedata.normalize('NFC', w), int(k)) for w, k in (line.split() for line in open(path, encoding='utf-8'))]
    # The alphabet: the script most letters are in, minus the letters too rare to be its own (0.01% of the letters:
    # names and quotes from other languages), minus the neighbour's.
    letters = collections.Counter()
    for w, k in words:
        for ch in w:
            if ch.isalpha() and unicodedata.category(ch) != 'Lm': letters[ch] += k  # Lm: the Arabic tatweel
    script = lambda ch: unicodedata.name(ch, '?').split()[0]
    scripts = collections.Counter()
    for ch, k in letters.items(): scripts[script(ch)] += k
    main, total = scripts.most_common(1)[0]
    alpha = {ch for ch, k in letters.items() if script(ch) == main and k >= total / 10000} - set(FOREIGN.get(lang, ''))
    return words, alpha

def table(words, alpha):
    c = collections.Counter()
    for w, k in words:
        if len(w) < 2 or any(ch not in alpha for ch in w): continue
        p = '^^' + w + '$'
        for i in range(len(p) - 2): c[p[i:i+3]] += math.sqrt(k)
    tot = sum(c.values())
    return ' '.join(f'{g}{round(-10*math.log(v/tot))}' for g, v in sorted(c.items())), round(-10*math.log(0.5/tot)), len(c)

def one_letter(words, alpha):
    # 0.1% of the corpus keeps the words ("a", "я") and drops the debris of tokenizing ("s" out of "it's").
    tot = sum(k for _, k in words)
    return ''.join(sorted(w for w, k in words if len(w) == 1 and w in alpha and k >= tot / 1000))

tables = '''/// How usual each three letters in a row are: -10 * ln(share), "^" and "$" are the word's edges.
/// Generated once from the 50k-word frequency lists of github.com/hermitdave/FrequencyWords (OpenSubtitles 2018,
/// CC-BY-SA), triplets weighted by the square root of the word count. Only these numbers are kept, not the words.
/// Keyed by the language macOS reports for the keyboard layout. Written by Tools/trigrams.py, never by hand.
let trigramTables: [String: (unseen: Double, triplets: String)] = [
'''
ones = '''/// The letters that are words on their own ("a", "я"), from the same lists: a lone one proves nothing.
let oneLetterWords: [String: Set<Character>] = [
'''
for spec in LANGS.split():
    lang, _, file = spec.partition('=')
    words, alpha = read(lang, f'{file or lang}_50k.txt')
    t, floor, n = table(words, alpha)
    print(lang, n, floor, ''.join(sorted(alpha)), one_letter(words, alpha))
    tables += f'    "{lang}": (unseen: {floor}, triplets: """\n' + textwrap.indent(textwrap.fill(t, 112), '        ') + '\n        """),\n'
    ones += f'    "{lang}": Set("{one_letter(words, alpha)}"),\n'
open('Sources/LayoutSwitcher/Trigrams.swift', 'w', encoding='utf-8').write(tables + ']\n\n' + ones + ']\n')
