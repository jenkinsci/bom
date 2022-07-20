def managedDeps = project.dependencyManagement.dependencies*.managementKey
println "Managed dependencies of $project: $managedDeps"
// Cannot use project.artifactMap since this ignores classifiers so has entries like org.jenkins-ci.plugins.workflow:workflow-step-api → org.jenkins-ci.plugins.workflow:workflow-step-api:jar:tests:2.20:test
def artifactMap = project.artifacts.grep {!it.hasClassifier()}.collectEntries {art -> ["$art.groupId:$art.artifactId".toString(), art]}
assert artifactMap['junit:junit'] == project.artifactMap['junit:junit']

def managedPluginDeps = managedDeps.collect {stripAllButGA(it)}.grep { ga ->
    def art = artifactMap[ga]
    if (art == null) {
        if (ga.contains('.plugins')) { // TODO without an Artifact, we have no reliable way of checking whether it is actually a plugin
            throw new org.apache.maven.plugin.MojoFailureException("Managed plugin dependency $ga not listed in test classpath of sample plugin")
        } else {
            println "Do not see managed dependency $ga"
            return false
        }
    }
    pluginName(art) != null
}
if (settings.activeProfiles.any {it ==~ /^2[.][0-9]+[.]x$/}) {
    println 'Skipping managed plugin dep sort check on this old LTS line'
} else {
    def sortedDeps = managedPluginDeps.toSorted { a, b ->
        def aSplit = a.split(':')
        def bSplit = b.split(':')
        def result = aSplit[0] <=> bSplit[0]
        if (result == 0) {
            result = aSplit[1] <=> bSplit[1]
        }
        result
    }
    if (managedPluginDeps != sortedDeps) {
        throw new org.apache.maven.plugin.MojoFailureException("""Managed plugin dependencies should be sorted: $managedPluginDeps, 

expected: $sortedDeps
""")
        // TODO also check sorting of sample plugin dependencies
    }
}

project.artifacts.each { art ->
    if (art.type != 'jar') {
        return
    }
    String plugin = pluginName(art)
    if (plugin == null) {
        return
    }
    if (plugin == 'instance-identity') {
        return // JEP-230
    }
    for (String intermediate : art.dependencyTrail.drop(1).dropRight(1).collect {stripAllButGA(it)}) {
        def intermediateArt = artifactMap[intermediate]
        if (intermediateArt == null) {
            println "Cannot find intermediate artifact $intermediate to check among ${artifactMap.keySet()}"
            continue
        }
        if (pluginName(intermediateArt) == null) {
            println "Ignoring dependency on plugin $plugin as it is a transitive dependency via non-plugin $intermediate"
            return
        }
    }
    if (!managedDeps.contains(art.dependencyConflictId)) {
        throw new org.apache.maven.plugin.MojoFailureException("Plugin dependency on ${stripAllButGA(art.dependencyConflictId)} is not from dependencyManagement")
    }
    println "Found a managed plugin dependency on $plugin"
}

String stripAllButGA(String gaEtc) {
    gaEtc.replaceFirst('^([^:]+:[^:]+):.+', '$1')
}

String pluginName(org.apache.maven.artifact.Artifact art) {
    assert art.file != null : "unresolved $art"
    new java.util.jar.JarFile(art.file).withCloseable { jar ->
        def attr = jar.manifest?.mainAttributes
        if (attr?.getValue('Plugin-Version') == null) {
            return null
        }
        attr?.getValue('Short-Name')
    }
}
