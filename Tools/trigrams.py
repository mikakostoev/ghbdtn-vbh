#!/usr/bin/env python3
"""Regenerates Sources/LayoutSwitcher/Trigrams.swift. Run from the project root after downloading the lists:
  curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ru/ru_50k.txt
  curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
  python3 Tools/trigrams.py
For another language add a line with its alphabet to the loop below; the lists themselves stay out of the repo."""
import math,collections,textwrap
def table(f,alpha):
    c=collections.Counter()
    for line in open(f,encoding='utf-8'):
        w,k=line.split()
        if len(w)<2 or any(ch not in alpha for ch in w): continue
        p='^^'+w+'$'
        for i in range(len(p)-2): c[p[i:i+3]]+=math.sqrt(int(k))
    tot=sum(c.values())
    return ' '.join(f'{g}{round(-10*math.log(v/tot))}' for g,v in sorted(c.items())), round(-10*math.log(0.5/tot)), len(c)
out='''/// How usual each three letters in a row are: -10 * ln(share), "^" and "$" are the word's edges.
/// Generated once from the 50k-word frequency lists of github.com/hermitdave/FrequencyWords (OpenSubtitles 2018,
/// CC-BY-SA), triplets weighted by the square root of the word count. Only these numbers are kept, not the words.
let trigramTables: [String: (unseen: Double, triplets: String)] = [
'''
for lang,f,alpha in (('ru','ru_50k.txt','абвгдеёжзийклмнопрстуфхцчшщъыьэюя'),('en','en_50k.txt','abcdefghijklmnopqrstuvwxyz')):
    t,floor,n=table(f,set(alpha)); print(lang,n,floor)
    out+=f'    "{lang}": (unseen: {floor}, triplets: """\n'+textwrap.indent(textwrap.fill(t,112),'        ')+'\n        """),\n'
out+=']\n'
open('Sources/LayoutSwitcher/Trigrams.swift','w',encoding='utf-8').write(out)
