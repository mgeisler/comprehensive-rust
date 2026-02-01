// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// ANCHOR: solution
// ANCHOR: setup
struct Spell {
    name: String,
    cost: u32,
}

struct Wizard {
    spells: Vec<Spell>,
    mana: u32,
}

impl Wizard {
    fn new(mana: u32) -> Self {
        Wizard { spells: vec![], mana }
    }
    // ANCHOR_END: setup

    // ANCHOR: add_spell
    fn add_spell(&mut self, spell: Spell) {
        self.spells.push(spell);
    }
    // ANCHOR_END: add_spell

    // ANCHOR: cast_spell
    fn cast_spell(&mut self, spell_name: &str) {
        let spell_option = self.spells.iter().find(|s| s.name == spell_name);

        if let Some(spell) = spell_option {
            if self.mana >= spell.cost {
                self.mana -= spell.cost;
                println!("Casting {}! Mana left: {}", spell.name, self.mana);
            } else {
                println!("Not enough mana to cast {}!", spell.name);
            }
        } else {
            println!("Spell {} not found!", spell_name);
        }
    }
    // ANCHOR_END: cast_spell
}

// ANCHOR: main
fn main() {
    let mut merlin = Wizard::new(20);
    let fireball = Spell { name: String::from("Fireball"), cost: 10 };
    let ice_blast = Spell { name: String::from("Ice Blast"), cost: 15 };

    merlin.add_spell(fireball);
    merlin.add_spell(ice_blast);

    merlin.cast_spell("Fireball"); // Casts successfully
    merlin.cast_spell("Ice Blast"); // Fails (not enough mana)
    merlin.cast_spell("Teleport"); // Fails (not found)
}

// ANCHOR: tests
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_spell() {
        let mut wizard = Wizard::new(10);
        let spell = Spell { name: String::from("Fireball"), cost: 5 };
        wizard.add_spell(spell);
        assert_eq!(wizard.spells.len(), 1);
    }

    #[test]
    fn test_cast_spell() {
        let mut wizard = Wizard::new(10);
        let spell = Spell { name: String::from("Fireball"), cost: 5 };
        wizard.add_spell(spell);

        wizard.cast_spell("Fireball");
        assert_eq!(wizard.mana, 5);
    }

    #[test]
    fn test_cast_spell_insufficient_mana() {
        let mut wizard = Wizard::new(10);
        let spell = Spell { name: String::from("Fireball"), cost: 15 };
        wizard.add_spell(spell);

        wizard.cast_spell("Fireball");
        assert_eq!(wizard.mana, 10);
    }

    #[test]
    fn test_cast_spell_not_found() {
        let mut wizard = Wizard::new(10);
        wizard.cast_spell("Fireball");
        assert_eq!(wizard.mana, 10);
    }
}
// ANCHOR_END: tests
