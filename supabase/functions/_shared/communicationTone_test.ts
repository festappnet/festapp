import assert from "node:assert/strict";
import {
  communicationTones,
  parseCommunicationTone,
  resolveCommunicationTone,
} from "./communicationTone.ts";
import cases from "../../../packages/festapp_contracts/communication-tone-cases.json" with {
  type: "json",
};
import contract from "../../../packages/festapp_contracts/communication-tone.json" with {
  type: "json",
};

Deno.test("communication tone follows the shared inheritance contract", () => {
  assert.deepEqual([...communicationTones], contract.values);
  for (const c of cases) {
    assert.equal(resolveCommunicationTone(c.value, c.inherited), c.expected);
  }
  for (const value of [undefined, true, 42, {}, [], ["informal"]]) {
    assert.equal(parseCommunicationTone(value), undefined);
    assert.equal(resolveCommunicationTone(value, "informal"), "informal");
  }
});
