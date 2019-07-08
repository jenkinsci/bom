def managedDeps = project.dependencyManagement.dependencies*.managementKey
println "Managed dependencies of $project: $managedDeps"
def artifactMap = project.artifactMap

def managedPluginDeps = managedDeps.collect {stripAllButGA(it)}.grep { ga ->
    def art = artifactMap[ga]
    if (art == null) {
        println "Do not see managed dependency $ga"
        return false
    }
    pluginName(art) != null
}
if (managedPluginDeps != managedPluginDeps.toSorted()) {
    throw new org.apache.maven.plugin.MojoFailureException("Managed plugin dependencies should be sorted: $managedPluginDeps")
}

project.artifacts.each { art ->
    if (art.type != 'jar') {
        return
    }
    String plugin = pluginName(art)
    if (plugin == null) {
        return
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
