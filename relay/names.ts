import { randomInt } from "node:crypto";

const ADJ = ["wobbly", "soggy", "feral", "dizzy", "grumpy", "sneaky", "lumpy", "zippy", "moldy", "spicy", "sleepy", "rowdy", "wonky", "fuzzy", "salty", "loopy"];
const ANIMAL = ["otter", "pigeon", "badger", "newt", "weasel", "marmot", "gecko", "hamster", "llama", "quokka", "ferret", "toad", "wombat", "ibis", "stoat", "axolotl"];

export function randomName(): string {
  return `${ADJ[randomInt(ADJ.length)]}-${ANIMAL[randomInt(ANIMAL.length)]}-${randomInt(100000, 1000000)}`;
}
