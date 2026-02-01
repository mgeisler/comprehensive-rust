---
minutes: 20
---

# Exercise: Wizard's Inventory

In this exercise, you will manage a wizard's inventory using what you have
learned about borrowing and ownership.

The wizard has a collection of spells. You need to implement functions to add
spells to the inventory and to cast spells from them.

```rust,editable,compile_fail
{{#include exercise.rs:setup}}

    // TODO: Implement `add_spell` to take ownership of a spell and add it to
    // the wizard's inventory.
    fn add_spell(..., spell: ...) {
        todo!()
    }

    // TODO: Implement `cast_spell` to borrow a spell from the inventory and
    // cast it. The wizard's mana should decrease by the spell's cost.
    // If the wizard doesn't have enough mana, the spell should fail.
    fn cast_spell(..., name: ...) {
        todo!()
    }
}

{{#include exercise.rs:main}}

{{#include exercise.rs:tests}}
```
