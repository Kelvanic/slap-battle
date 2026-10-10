const ADJ = ["wobbly", "soggy", "feral", "dizzy", "grumpy", "sneaky", "lumpy", "zippy", "moldy", "spicy", "sleepy", "rowdy", "wonky", "fuzzy", "salty", "loopy"];
const ANIMAL = ["otter", "pigeon", "badger", "newt", "weasel", "marmot", "gecko", "hamster", "llama", "quokka", "ferret", "toad", "wombat", "ibis", "stoat", "axolotl"];

export function randomName(taken: Set<string>): string {
  for (let i = 0; i < 100; i++) {
    const n = `${ADJ[(Math.random() * ADJ.length) | 0]}-${ANIMAL[(Math.random() * ANIMAL.length) | 0]}-${10 + ((Math.random() * 90) | 0)}`;
    if (!taken.has(n)) return n;
  }
  return `anon-${Date.now().toString(36)}`;
}
