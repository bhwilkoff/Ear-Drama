# Computer-shaped problems

There is a habit of mind that most people who make software know well,
because most of us have it. Nilay Patel, the editor-in-chief of The
Verge, calls it
[software brain](https://www.theverge.com/podcast/917029/software-brain-ai-backlash-databases-automation):
seeing the whole world as a set of databases, each one waiting for the
right code to take control of it. A classroom becomes a table of names
and scores, a friendship becomes a feed, and a film becomes a row that
needs a summary. Once you see the world that way, every problem looks
like one a computer could finish for you, if only you described it well
enough.

**Some problems were never computer-shaped.**

AI has turned software brain up as far as it will go. An agent can write
the code for almost anything you can describe, and it can write the
words too, so it is very tempting to treat every problem as a database
waiting to be put to work. But, learning, community, friendship, taste,
and the people we love are not like that. They only happen when a person
does the work, and a first draft that no person has wrestled with is not
the start of that work. Until someone shapes it, it is just slop.

## Computer-shaped and human-shaped

A human-shaped problem is something, really anything, in your life that
will in some way make your life better, happier, or more deeply resonant
with the universe if you could only solve for it. It is something that
is the gentle hum of worry or concern that you have about an area of
your life. It is a thing that you wonder and question about often. It is
something that has gone unsolved for months or even years, something
that is present in a gnawing way. And most of all, it is something that
you cannot do yourself. Your current tools and resources are
insufficiently up to the challenge.

Good human-shaped problems:

- I do not have time to read books in my life. I need something that
  fits my way of existing that will still let me enjoy great novels and
  non-fiction every day.
- I lack inspiration for what to do with my child to entertain them
  without screens. I need something that will constantly suggest new
  things to do that cater to both of our interests.
- I read a lot of news and "takes" from people online and I even see
  newsworthy things out in the real world, and I would love a way to
  chronicle it all into a cohesive narrative, an understanding of how I
  see things to remind myself why I believe what I believe.
- I want an easy way to align my political beliefs with who and what
  I'm voting for when I get my ballot or vote in person.

Computer-shaped problems:

- I want to measure the amount of negative sentiment online for any
  given public figure.
- I want to find the best price for my grocery list on delivery apps so
  that I can comparison shop and combine trips for the cheapest (and
  least convenient) trips for the delivery drivers.
- I want to categorize every conversation I have and chronicle them as a
  way of measuring my impact on others.
- I want to map socioeconomic data by neighborhood so that I can use it
  to choose the optimal route for Halloween trick or treating to ensure
  high-end candy.

**Human-shaped problems see the world as interrelated stories to be
told, experienced, and added to.**

**Computer-shaped problems see the world as disparate data points to be
aggregated, quantified, and leveraged.**

Almost every app is both. Most of its code is computer-shaped work, and
an agent can write nearly all of it. Sorting ten thousand films by
decade is computer-shaped. So is checking that a caption appears at the
moment the words are spoken, or keeping two devices on the same second
of the same film. Hand those to the machine, and be glad you can. The
human-shaped part is small, and it is the reason the app exists.

The phrase "computer-shaped problem" comes from a
[reply on Bluesky](https://bsky.app/profile/mosheroperandi.bsky.social/post/3mgasswgabs23)
by @mosheroperandi.bsky.social on March 4, 2026, which said we have
spent decades turning everything we can into computer-shaped problems.
When you use the phrase, credit the reply and link to it.

## What we want instead

I want software that uses AI as a tool, one that people wield for human
purposes. It should take the mechanical work off people's hands so that
the human part has more room, and it should never be used to replace the
people involved or to flatten what they make.

The way there is values. Every piece of software is built on values,
whether or not anyone wrote them down, and software brain has values of
its own: efficiency, scale, and whatever is cheapest to produce.
Human-shaped software writes its values down and wears them on its
sleeve, so that the people who use it, and the AI agents that help build
it, can both see what it is for. The
[Human-Shaped Principles](PRINCIPLES.md) are the values every piece of
software built this way shares, and each builder adds the ones their own
problem needs.

## The person keeps it human-shaped

Once you have named the human-shaped problem you are building for, you
do not need to question your agent about every line it writes. The
person in the work is what keeps it human-shaped. You write down what
you value and what you want, you play with what comes back until it is
right, and you publish it so that other people can play with it too
(stage 00 calls this **write, play, publish**). Software brain leaves
the person out, and this method is built around them.

## Case study: Archive Watch's film notes

[Archive Watch](case-study-archive-watch.md) is a free app for watching
public-domain films from the Internet Archive, on phones, computers, and
TVs. Every film in it needs a few lines of notes, so that people can
decide what is worth their evening, and there are tens of thousands of
films. On September 26, 2026, I made this a standing instruction for the
agent building it:

> I don't want AI making lists and writing copy. Any time we can use
> metadata or user copy/categorization from archive.org.

So, each film's notes come from the people who uploaded and reviewed it
on archive.org, rather than from a summary written by AI. Those notes
are sometimes wrong, and correcting them takes time that a model would
never need.

And yet, ten thousand summaries written by AI would be more efficient
and a worse experience, both for the internet and for people. It is
worse for the internet because the web is filling with words that no one
wrote and no one reads (the
"[Dead Internet Theory](https://en.wikipedia.org/wiki/Dead_Internet_theory)"),
and because search is learning to answer every question itself and send
no one on to the people who did the work
("[Google Zero](https://www.theverge.com/24167865/google-zero-search-crash-housefresh-ai-overviews-traffic-data-audience)").
It is worse for people because it removes the folks who actually watched
those films and loved them. The AI did not watch the movies, and it
cannot enjoy them the way a person can. Keeping their words is how the
app says what it values: the people who watched, and the writing they
did about it.

Keeping the human-shaped part is slower. Pulling the notes from the
people who wrote them meant building and maintaining a pipeline, when a
model could have written every note in an afternoon. And the line is not
always obvious, because a summary of a long document might be exactly
what someone needs, and leave them more capable rather than less. Naming
the shape of a problem does not decide for you. It makes you decide on
purpose.

## Where to go next

- [Stage 00, Why we build](../path/00-why-we-build.md) puts this idea to
  work on the first day of an app.
- [The Human-Shaped Principles](PRINCIPLES.md) are the values every
  human-shaped app wears on its sleeve.
- [More than asking an AI for an app](not-vibe-coding.md) says why
  building this way differs from asking an AI to make you one.
- [The Archive Watch case study](case-study-archive-watch.md) tells how
  one app was built this way, month by month.

Pick one thing you want to build, and name its shape.
