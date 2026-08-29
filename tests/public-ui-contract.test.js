#!/usr/bin/env node
const fs = require('node:fs');
const assert = require('node:assert/strict');

const publicPages = [
  'index.html', 'support.html', 'blog.html', 'checkout.html',
  'privacy.html', 'legal.html',
  ...fs.readdirSync('blog').map(name => `blog/${name}/index.html`),
];

for (const file of publicPages) {
  const html = fs.readFileSync(file, 'utf8');
  const placeholderLinks = [...html.matchAll(/<a\b[^>]*href="#"[^>]*>/g)]
    .filter(match => !match[0].includes('data-paypal-donate'));
  assert.equal(placeholderLinks.length, 0, `${file} contains a placeholder link`);
}

const home = fs.readFileSync('index.html', 'utf8');
const support = fs.readFileSync('support.html', 'utf8');
const main = fs.readFileSync('main.js', 'utf8');
assert.ok(home.includes('class="home-facts"'), 'homepage must expose truthful at-a-glance facts');
assert.ok(home.includes('data-mailto-form'), 'homepage inquiry form must have a real action');
assert.ok(support.includes('data-mailto-form'), 'volunteer form must have a real action');
assert.ok(main.includes("form.matches('[data-mailto-form]')"), 'mailto forms must be handled');
assert.ok(!support.includes('Description coming soon.</p><button'), 'unavailable products must not have Add buttons');
console.log(`Public UI contract OK: ${publicPages.length} pages checked.`);
