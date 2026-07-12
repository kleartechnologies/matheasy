/**
 * Minimal ambient types for `mathsteps` (0.2.0 ships no types).
 *
 * mathsteps bundles its OWN old mathjs internally, so its node objects are NOT
 * compatible with the mathjs 15 we use for verification — we only ever read the
 * `.ascii()` / `.toString()` strings off these and re-parse with mathjs 15.
 */
declare module "mathsteps" {
  /** An `lhs <comparator> rhs` equation node. */
  export interface MsEquation {
    ascii(): string;
    comparator: string;
  }

  /** An expression node (simplify path). */
  export interface MsNode {
    toString(): string;
    ascii?(): string;
  }

  export interface MsStep {
    changeType: string;
    /** Present on equation-solving steps. */
    oldEquation?: MsEquation;
    newEquation?: MsEquation;
    /** Present on simplify steps. */
    oldNode?: MsNode;
    newNode?: MsNode;
    substeps: MsStep[];
  }

  export function solveEquation(equationString: string): MsStep[];
  export function simplifyExpression(expressionString: string): MsStep[];
  export const ChangeTypes: Record<string, string>;
}
