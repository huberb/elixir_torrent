Bencoder
========

[![Build Status](https://travis-ci.org/alehander42/bencoder.svg)](https://travis-ci.org/alehander42/bencoder)

An elixir bencoding package

It's intended for the [`yolandi`](https://github.com/alehander42/yolandi) torrent client

 **Beware**

 That's a learning exercise for me in elixir/erlang, so the code is still not clean and non idiomatic

 Bencode format supports 4 types of data: numbers, dictionaries and lists.
 `Bencoder` uses elixir's `Integer`, `Map`, `List` and `BitString`.

 Examples:

 ```elixir
 Bencoder.encode(2) # "i2e"
 Bencoder.encode([4, 202]) # "li4ei202ee"
 ```

 ```elixir
 Bencoder.decode("4:life") # "life"
 Bencoder.decode("d4:lifei42ee") # %{"life" => 42}
 Bencoder.decode("i42e") # 42
 Bencoder.decode("l1:~e") # ["~"]
```


