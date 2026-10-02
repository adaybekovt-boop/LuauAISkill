#!/usr/bin/env node
// Exercise a live Worker with the official MCP client. Pass an origin or /mcp URL; optional key is read from env.
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const supplied = process.argv[2] || 'http://127.0.0.1:8787/mcp';
const url = new URL(supplied);
if (url.pathname === '/') url.pathname = '/mcp';
const client = new Client({name: 'LuauAISkill-release-smoke', version: '1.0.0'});
const headers = process.env.MCP_API_KEY ? {Authorization: `Bearer ${process.env.MCP_API_KEY}`} : {};
await client.connect(new StreamableHTTPClientTransport(url, {requestInit: {headers}}));
try {
  const tools = await client.listTools();
  assert.equal(tools.tools.length, 7);
  const cases = [
    ['api_lookup', {query: 'Humanoid.LoadAnimation'}, /DEPRECATED/],
    ['api_search', {term: 'Pathfinding', limit: 5}, /PathfindingService/],
    ['api_deprecated', {class_name: 'Humanoid'}, /LoadAnimation/],
    ['scan_legacy', {code: 'spawn(function() end)\nwhile wait(1) do end'}, /sched-spawn/],
    ['search_skill', {query: 'session locking'}, /save-system|data-persistence/],
    ['read_skill_doc', {path: 'SKILL.md', heading: 'Hard rules'}, /Never invent APIs/],
    ['list_skill_docs', {prefix: 'recipes/gameplay/'}, /save-system.md/],
  ];
  for (const [name, args, expected] of cases) {
    const result = await client.callTool({name, arguments: args});
    assert.ok(!result.isError, name);
    assert.match(result.content.find(c => c.type === 'text').text, expected, name);
    console.log(`PASS ${name}`);
  }
  const resource = await client.readResource({uri: 'skill://SKILL.md'});
  assert.match(resource.contents[0].text, /Hard rules/);
  console.log('PASS skill resource; initialize and discovery completed via official MCP SDK');
} finally { await client.close(); }
