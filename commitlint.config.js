// commitlint.config.js — repo-bootstrap baseline
//
// Conventional Commits enforcement, aligned with the global CLAUDE.md rules.
// Consumed by the commitlint pre-commit hook on the commit-msg stage.

module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',      // new feature
        'fix',       // bug fix
        'chore',     // tooling, deps, housekeeping
        'docs',      // documentation only
        'refactor',  // code change that neither fixes a bug nor adds a feature
        'test',      // adding or correcting tests
        'perf',      // performance improvement
        'ci',        // CI/CD pipeline change
        'build',     // build system / external dependencies
        'revert',    // revert a previous commit
        'style',     // formatting / whitespace only
      ],
    ],
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-case': [2, 'always', 'lower-case'],
    'subject-case': [2, 'never', ['upper-case', 'pascal-case', 'start-case']],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],
    'subject-max-length': [2, 'always', 72],
    'header-max-length': [2, 'always', 100],
    'body-leading-blank': [2, 'always'],
    'body-max-line-length': [2, 'always', 72],
    'footer-leading-blank': [2, 'always'],
    'footer-max-line-length': [2, 'always', 72],
  },
};
