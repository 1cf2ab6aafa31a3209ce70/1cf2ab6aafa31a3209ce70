# Content provenance

Every title needs its own identity, assets, levels and presentation. Similar mechanics do not authorize copying a game's art, layouts, names, translations, sound or store material. The [preflight decision](../roadmap/decisions/ADR-001-first-party-foundation.md) allows design references only and the [third-party inclusion inventory](../roadmap/audits/preflight-inclusion-bom.md) is empty.

The repository’s [MIT license](../LICENSE) covers project-authored code, documentation and resources unless a file or content record explicitly states otherwise. Contributions are made under the same terms. Third-party material retains its own rights, licenses and required notices; the project cannot relicense it merely by adding it to this repository. Review fonts, sound, icons, levels and promotional content separately, and retain evidence that permits the intended use.

## Record template

Create a record beside a title's content or in its documented inventory, and update it when the material changes. Use the `Games/<Title>` boundary; the empty development target has no finished title assets. Do not create an approved inventory entry solely because a file exists.

```markdown
# Content record: <name>

- Local paths and title: <exact files or generated outputs>
- Content type: <art / sound / font / level / text / branding / other>
- Creator and creation date: <person or organization; date>
- Origin: <original work or upstream URL and pinned revision>
- Creation method: <tools, generation recipe, source inputs>
- Rights holder: <identified holder; evidence location>
- Redistribution terms: <MIT for project-authored material; exact third-party license/permission otherwise>
- Evidence and notices: <license, permission, attribution and notice paths>
- Modifications: <changes from source and author>
- Reproducibility: <generator/version/seed if applicable>
- Review: <reviewer, date, intended use, approved or unresolved, limitations>
```

For original content, record authorship and source inputs, and confirm the contributor can provide it under MIT. For generated content, retain enough method/input information to review origin and reproduce it where practical. For externally sourced content, document permission for the intended modification and redistribution, required attribution and any restrictions; unresolved material stays out of distributable targets.

The current platform experiment uses authored code and generated geometry/colors rather than imported artwork. Its provenance boundary is described in the [experiment README](../experiments/platform-baseline/README.md); it is MIT-licensed project-authored material, but is not approved as finished title content. Future copied code, tests or tooling also require inclusion-review records even when they are not game assets.
