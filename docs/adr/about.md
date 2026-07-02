# About

**Decisions** are documents that capture the details of important choices that were made during the development of this software, along with the context and consequences to be remembered. 

These decision documents are an excellent opportunity to write down what was in your head during the development of a code change, the design of a feature, or the choice of one vendor/library over another. Having these details written down greatly benefits future code contributors, including your future self, as they question why something was done a certain way in the past. 

A good decision usually captures:

* Problem Context
* Decision Made
* Known Consequences & Tradeoffs Considered

Generally, decision documents should be considered immutable, but if you feel there is justified value in editing a previous file, consider timestamped additions instead of outright deletion of previous copy.

Contributors to LocalCents are encouraged to generate decision documents alongside or following significant code changes. You can find a reference template in the repo and consult existing documents for format examples.

Decision files are named with a four-digit sequential prefix that increments by one in creation order, followed by a short kebab-case slug (e.g. `0001-which-automerge-rust-library.md`). To add a decision, take the next number after the highest existing one.

For more on the practice of writing decisions (also known as architecture decision records in other circles) see [this GitHub repo][adr].

[adr]: https://github.com/joelparkerhenderson/architecture-decision-record
