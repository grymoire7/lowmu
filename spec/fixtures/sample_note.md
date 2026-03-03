---
title: Quick Ruby Tip
date: 2026-03-03
type: note
tags: [ruby]
---
Just discovered that Ruby's Comparable module makes sorting custom objects dead simple. Include it, define `<=>`, and you get `<`, `>`, `<=`, `>=`, `between?`, and `clamp` for free. Worth revisiting if you haven't used it lately. #ruby #til
