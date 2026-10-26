#!/usr/bin/env node

import { readFileSync } from "node:fs";

const [schemaPath, valuePath] = process.argv.slice(2);
if (!schemaPath || !valuePath) {
  console.error("Usage: validate_json_schema_subset.mjs SCHEMA.json VALUE.json");
  process.exit(64);
}

const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const value = JSON.parse(readFileSync(valuePath, "utf8"));

function fail(path, message) {
  throw new Error(`${path}: ${message}`);
}

function validate(node, candidate, path = "$") {
  if (Object.hasOwn(node, "const") && candidate !== node.const) {
    fail(path, "does not match const");
  }
  if (node.enum && !node.enum.includes(candidate)) {
    fail(path, "is not an allowed value");
  }
  if (node.type === "object") {
    if (candidate === null || typeof candidate !== "object" || Array.isArray(candidate)) {
      fail(path, "must be an object");
    }
    for (const key of node.required || []) {
      if (!Object.hasOwn(candidate, key)) fail(path, `missing required property ${key}`);
    }
    const properties = node.properties || {};
    if (node.additionalProperties === false) {
      for (const key of Object.keys(candidate)) {
        if (!Object.hasOwn(properties, key)) fail(path, `unexpected property ${key}`);
      }
    }
    for (const [key, child] of Object.entries(properties)) {
      if (Object.hasOwn(candidate, key)) validate(child, candidate[key], `${path}.${key}`);
    }
  } else if (node.type === "string") {
    if (typeof candidate !== "string") fail(path, "must be a string");
    if (node.minLength !== undefined && candidate.length < node.minLength) fail(path, "is too short");
    if (node.maxLength !== undefined && candidate.length > node.maxLength) fail(path, "is too long");
    if (node.pattern && !new RegExp(node.pattern).test(candidate)) fail(path, "does not match pattern");
  }
}

try {
  validate(schema, value);
} catch (error) {
  console.error(`Schema validation failed: ${error.message}`);
  process.exit(1);
}
