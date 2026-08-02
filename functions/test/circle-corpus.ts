/**
 * A MECHANICALLY GENERATED adversarial corpus for the circle engine.
 *
 * Every previous round's probe set is a list of cases some LLM already thought of. That is
 * exactly why regressions kept slipping through: broadening a reader to rescue a solvable
 * problem re-opens a trap whose ONE known phrasing is in the probe set, and the probe set
 * keeps passing. What was missing is COVERAGE OF THE VOCABULARY — the same trap said a
 * hundred ways.
 *
 * So the corpus is a cross-product: each trap family × the synonym sets the guards actually
 * key on. No truth labels are needed for the differential (that only asks whether the working
 * tree ANSWERS where production DECLINED); the `mustDecline` flag marks the families where
 * declining is unambiguously correct whatever the wording.
 */

export type Case = { text: string; family: string; mustDecline: boolean };

const cross = (...lists: string[][]): string[][] =>
  lists.reduce<string[][]>((acc, l) => acc.flatMap((a) => l.map((x) => [...a, x])), [[]]);

const cases: Case[] = [];
const add = (family: string, mustDecline: boolean, texts: string[]): void => {
  for (const text of texts) cases.push({ text, family, mustDecline });
};

// 1) SUB-REGION named by a restrictive clause on a whole-figure head noun.
add(
  "sub-region-clause",
  true,
  cross(
    ["wets", "soaks", "grazes", "shades", "darkens", "sprays", "waters", "covers", "reaches", "touches", "lights", "sweeps", "paints", "burns", "cools", "chills", "warms", "dries", "cleans", "scans"],
    ["circle", "field", "lawn", "garden", "floor", "disc"]
  ).map(
    ([v, n]) =>
      `A sprinkler at the centre of a circular ${n} of radius 6 m turns through 60 degrees. Find the area of the ${n} it ${v}.`
  )
);

// 2) An ANNULUS stated as a band width — the width idiom varies more than the noun does.
add(
  "annulus-band",
  true,
  cross(
    ["rim", "border", "band", "edging", "strip", "margin", "ring", "frame", "verge", "kerb"],
    ["wide", "across", "thick", "broad", "in width", "in breadth", "in thickness"]
  ).map(
    ([n, w]) =>
      `A circular table of radius 40 cm has a wooden ${n} 5 cm ${w} all the way round. Find the area of the wood.`
  )
);

// 3) A 3-D OUTER LAYER — the ask is a surface, whatever the figure is called.
add(
  "solid-skin",
  true,
  cross(
    ["skin", "peel", "rind", "shell", "husk", "crust", "hide", "coat", "casing", "jacket"],
    ["watermelon", "orange", "melon", "pumpkin", "coconut", "drum", "tank", "ball", "cake", "loaf"]
  ).map(
    ([layer, fig]) => `A circular ${fig} has a radius of 12 cm. Find the area of its ${layer}.`
  )
);

// 4) A SOLID's extent along the axis the circle does not have.
add(
  "solid-extent",
  true,
  cross(
    ["thick", "deep", "tall", "high", "long"],
    ["tin", "drum", "log", "cake", "disc", "pipe", "tub", "vat", "coin", "wheel"]
  ).map(
    ([adj, fig]) =>
      `A circular ${fig} of radius 5 cm is 12 cm ${adj}. Find the area of the paper that wraps its side.`
  )
);

// 5) A COMPARATIVE OFFSET from a numeric base — arithmetic nothing downstream re-checks.
add(
  "comparative-offset",
  true,
  cross(
    ["below", "above", "under", "over", "more than", "less than", "greater than", "smaller than", "short of", "beyond"],
    ["90 degrees", "a right angle", "180 degrees", "a straight angle"]
  ).map(
    ([cmp, base]) =>
      `A sector of a circle of radius 6 cm has a central angle 10 degrees ${cmp} ${base}. Find the area of the sector.`
  )
);

// 6) A CHORD naming its endpoints by compass bearing is a diameter said without the word.
add(
  "compass-chord",
  true,
  cross(
    ["north", "east", "northern", "top"],
    ["south", "west", "southern", "bottom"],
    ["point", "end", "edge", "side"]
  ).map(
    ([a, b, kind]) =>
      `A circular field of radius 20 m is crossed by a straight path from the ${a} ${kind} of its edge to the ${b} ${kind} of its edge. Find the area of the ground to the east of the path.`
  )
);

// 7) A FIGURE being re-oriented is not a sweep — the noun list can never be complete.
add(
  "rotated-figure",
  true,
  cross(
    ["dish", "tray", "plate", "card", "disc", "wheel", "sheet", "panel", "board", "lid", "dial", "coin"],
    ["turned", "rotated", "swung", "revolved", "pivoted"]
  ).map(
    ([fig, v]) =>
      `An arc of a circle of radius 21 cm subtends 60 degrees at the centre O. The ${fig} is then ${v} through 240 degrees about O. Find the length of the arc.`
  )
);

// 8) …but a genuine SWEEPER states the swept angle. These must NOT decline (checked by hand
//    against the differential, not asserted here — a decline is honest, just lost coverage).
add(
  "true-sweep",
  false,
  cross(
    ["sprinkler", "beam", "wiper", "radar", "searchlight", "fan", "scanner", "hose", "arm", "lamp"],
    ["sweeps", "rotates", "scans", "turns", "swings"]
  ).map(
    ([agent, v]) =>
      `A ${agent} at the centre of a circular field ${v} through 120 degrees. The field has a radius of 9 m. Find the area of the sector swept.`
  )
);

// 9) A THREE-LETTER angle name states its own vertex.
add(
  "vertex-angle",
  false,
  cross(["AOB", "BOC", "POQ"], ["OAB", "OBA", "ACB", "APB"]).map(
    ([central, base]) =>
      `O is the centre of a circle of radius 12 cm. Angle ${central} is 40. Angle ${base} is 70 degrees. Find the length of the arc.`
  )
);

// 10) A dimension welded to a BYSTANDER noun must never size the asked figure.
add(
  "dimension-owner",
  true,
  cross(
    ["coin", "button", "lid", "badge", "counter", "washer", "token", "cap"],
    ["table", "plate", "tray", "mat", "board", "dish"],
    ["lies on", "sits on", "is placed on", "rests on"]
  ).map(
    ([small, big, verb]) =>
      `A ${small} 2 cm in diameter ${verb} a circular ${big}. Find the area of the ${big}.`
  )
);

// 11) A REACH / TETHER is a second radius however it is stated.
add(
  "second-radius",
  true,
  cross(
    ["rope", "chain", "cord", "lead", "leash", "tether", "hose", "wire", "cable", "strap"],
    ["tethered", "tied", "chained", "roped", "fastened", "attached"]
  ).map(
    ([inst, v]) =>
      `A circular field has a radius of 20 m. A goat is ${v} at its centre with a 5 m ${inst}. Find the area the goat can graze.`
  )
);

// 12) A REPORTED question is a statement about the figure, not the ask.
add(
  "reported-question",
  false,
  cross(
    ["shows", "gives", "tells you", "states", "records", "indicates", "displays", "marks", "notes", "illustrates"],
    ["how long the perimeter is", "what the circumference is", "how far it is round the edge"]
  ).map(
    ([v, clause]) =>
      `Find the area of a circle of radius 7 cm. The diagram ${v} ${clause}.`
  )
);

// 13) A NAMED FRACTION of the circle is a sub-region.
add(
  "named-fraction",
  true,
  cross(
    ["north-eastern", "southern", "upper", "lower", "shaded", "left-hand", "outer", "far"],
    ["quarter", "third", "half", "sixth", "eighth"]
  ).map(
    ([q, part]) => `A circular garden has a radius of 14 m. Find the area of its ${q} ${part}.`
  )
);

// 14) NON-DEGREE angular units — revolutions and radians.
add(
  "foreign-angle-unit",
  true,
  cross(
    ["turns", "revolutions", "rotations", "revs", "radians", "rad", "gradians", "grads", "mils"],
    ["2", "0.5", "1/3", "1.25"]
  ).map(
    ([unit, n]) =>
      `A sector of a circle of radius 6 cm has a central angle of ${n} ${unit}. Find the area of the sector.`
  )
);

// 15) A COUNT riding the number is a label, not the angle.
add(
  "count-label",
  false,
  cross(
    ["pupils", "students", "cars", "votes", "boys", "girls", "families", "houses", "books", "birds"],
    ["8", "12", "20", "35"]
  ).map(
    ([noun, n]) =>
      `A sector of a circle of radius 6 cm: the angle at the centre of the sector for ${n} ${noun} is 90. Find the area of the sector.`
  )
);

// 16) A COVERING material — the dimension is fixed by what the material DOES.
add(
  "covering-material",
  false,
  cross(
    ["carpet", "turf", "felt", "fencing", "edging", "ribbon", "mesh", "paint", "tape", "glass"],
    ["for", "to cover", "to go round", "to lay on", "to fit around"],
    ["floor", "rim", "edge", "lawn", "top", "boundary"]
  ).map(
    ([mat, rel, obj]) =>
      `How many metres of ${mat} are needed ${rel} the ${obj} of a circular room of radius 3 m?`
  )
);

// 17) A SECOND FIGURE whose dimension the text never gives.
add(
  "second-figure",
  true,
  cross(
    ["larger", "bigger", "smaller", "outer", "inner", "second", "other"],
    ["circle", "disc", "ring"]
  ).map(
    ([adj, n]) =>
      `A circle of radius 4 cm is drawn inside a ${adj} ${n}. Find the area of the ${adj} ${n}.`
  )
);

// 18) A SUB-REGION named with "the part of".
add(
  "part-of-ask",
  true,
  cross(
    ["part", "portion", "piece", "region", "section", "share", "slice", "bit"],
    ["face", "field", "lawn", "disc", "plate"]
  ).map(
    ([part, fig]) =>
      `A circular ${fig} has a radius of 10 cm. Find the area of the ${part} of the ${fig} that the pointer passes over in 15 minutes.`
  )
);

// 19) PLAIN, SOLVABLE circles — the coverage floor. Any of these that stops answering is a
//     real loss, so the differential reports them separately from the trap families.
add(
  "plain-solvable",
  false,
  cross(
    ["area", "circumference"],
    ["radius", "diameter"],
    ["7", "14", "2.5", "10", "3.5"],
    ["cm", "m", "mm"]
  ).map(([q, dim, v, u]) => `Find the ${q} of a circle of ${dim} ${v} ${u}.`)
);
add(
  "plain-solvable",
  false,
  cross(["60", "90", "120", "45"], ["6", "12", "10"]).map(
    ([ang, r]) =>
      `A sector of a circle of radius ${r} cm has a central angle of ${ang} degrees. Find the area of the sector.`
  )
);

export const CORPUS: Case[] = cases;
