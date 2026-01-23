# Bill of Materials for Jenkins plugins

This repository implements a [Maven BOM](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Importing_Dependencies)
which can be used in a plugin POM to more easily manage dependencies on other common plugins.
This is important because version management is a [common annoyance](https://jenkins.io/doc/developer/plugin-development/updating-parent/#understanding-requireupperbounddeps-failures-and-fixes).
See [JENKINS-47498](https://issues.jenkins.io/browse/JENKINS-47498) for the background.

A secondary purpose of this repository is to regularly perform plugin compatibility testing (PCT) against new or forthcoming releases of core and plugins.

If you are interested in a Bill of Materials for Jenkins core components, see [this page](https://jenkins.io/doc/developer/plugin-development/dependency-management/#jenkins-core-bom).

# Usage

After [selecting your plugin’s LTS baseline](https://www.jenkins.io/doc/developer/plugin-development/choosing-jenkins-baseline/):

```xml
<jenkins.baseline>2.516</jenkins.baseline>
<jenkins.version>${jenkins.baseline}.3</jenkins.version>
```

just import the [latest BOM](https://repo.jenkins-ci.org/public/io/jenkins/tools/bom) from that line:

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.jenkins.tools.bom</groupId>
            <artifactId>bom-${jenkins.baseline}.x</artifactId>
            <version>…</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

Now you can declare dependencies on many plugins without needing to specify a version:

```xml
<dependency>
    <groupId>org.jenkins-ci.plugins.workflow</groupId>
    <artifactId>workflow-cps</artifactId>
    <scope>test</scope>
</dependency>
```

You can always override a version managed by the BOM if you wish,
but if you find the need to use a newer version,
first try just updating the version in the BOM and cutting a new release of it.

When starting to use the BOM in an existing plugin,
you may find that many existing dependencies do not need to be expressed at all and can be deleted,
if they were added solely to satisfy the `RequireUpperBoundDeps` Enforcer rule or similar.
Maven will automatically add transitive dependencies to your classpath,
so you should only need to declare an explicit dependency on another plugin when:

* You compile against it. (Use `test` scope if it is only used in tests.)
* It is required to be present and not otherwise loaded transitively.
  (For example, `workflow-basic-steps` and `workflow-durable-task-step` are commonly required for tests which run Pipeline builds.)

The command

```sh
mvn dependency:analyze
```

can offer clues about unused plugin dependencies,
though you must evaluate each carefully since it only understands Java binary dependencies
(what is required for compilation, more or less).

A [BOM tutorial video](https://www.jenkins.io/doc/developer/tutorial-improve/use-plugin-bill-of-materials/) is available in the [Jenkins developer documentation](https://www.jenkins.io/doc/developer/tutorial-improve/).

## Depending on `bom-weekly`

The `bom-weekly` line is a special artifact that follows the weekly release of Jenkins core.
You would only depend on it when you are actively tracking the weekly release line.

Some examples of when you would use it:
- You run tests in your plugin against the weekly version of Jenkins
- You depend on the Jenkins core weekly line and update it regularly, ([example](https://github.com/jenkins-infra/pipeline-steps-doc-generator))

You would not use it:
- When you are temporarily depending on the weekly line but do not plan to update it on every release
  - This would cause dependency update build failures when a plugin is updated only on the weekly line (if you depend on it)

## Depending on older versions

Sometimes a plugin maintainer may prefer to require an older version of Jenkins as its minimum version.
Refer to [choosing a Jenkins version](https://www.jenkins.io/doc/developer/plugin-development/choosing-jenkins-baseline/) for more details.

When an older Jenkins version is used, then the matching older version of the plugin bill of materials should be used.

| BOM Line    | Version               | Comment                      |
| ----------- | --------------------- | ---------------------------- |
| bom-2.346.x | 1763.v092b_8980a_f5e  | Last LTS to support Java 8   |
| bom-2.361.x | 2102.v854b_fec19c92   | First LTS to require Java 11 |
| bom-2.375.x | 2198.v39c76fc308ca    |                              |
| bom-2.387.x | 2543.vfb_1a_5fb_9496d |                              |
| bom-2.401.x | 2745.vc7b_fe4c876fa_  |                              |
| bom-2.414.x | 2982.vdce2153031a_0   |                              |
| bom-2.426.x | 3208.vb_21177d4b_cd9  |                              |
| bom-2.440.x | 3435.v238d66a_043fb_  |                              |
| bom-2.452.x | 3944.v1a_e4f8b_452db_ |                              |
| bom-2.462.x | 4228.v0a_71308d905b_  | Last LTS to support Java 11  |
| bom-2.479.x | 5054.v620b_5d2b_d5e6  | First LTS to require Java 17 |
| bom-2.492.x | 5473.vb_9533d9e5d88   |                              |
| bom-2.504.x | 5933.vcf06f7b_5d1a_2  |                              |

The latest versions of all BOM lines are available from the [Jenkins artifact repository](https://repo.jenkins-ci.org/public/io/jenkins/tools/bom).

# Development

[Moved to CONTRIBUTING](CONTRIBUTING.md)
