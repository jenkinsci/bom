package io.jenkins.tools.bom.sample;

import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition;
import org.jenkinsci.plugins.workflow.job.WorkflowJob;
import org.jenkinsci.plugins.workflow.job.WorkflowRun;
import org.junit.Rule;
import org.junit.Test;
import org.jvnet.hudson.test.JenkinsRule;
import org.jvnet.hudson.test.RealJenkinsRule;

public class DeclarativePipelineTest {

    @Rule
    public RealJenkinsRule r = new RealJenkinsRule();

    @Test
    public void smokes() throws Throwable {
        r.then(r -> {
            final WorkflowRun run = runPipeline(
                    r,
                    m(
                            "pipeline {",
                            "  agent none",
                            "  stages {",
                            "    stage('Example') {",
                            "      steps {",
                            "        example(x: 'foobar')",
                            "      }",
                            "    }",
                            "  }",
                            "}"));

            r.assertBuildStatusSuccess(run);
            r.assertLogContains("Ran on foobar!", run);
        });
    }

    /**
     * Run a pipeline job synchronously.
     *
     * @param definition the pipeline job definition
     * @return the started job
     */
    private static WorkflowRun runPipeline(JenkinsRule r, String definition) throws Exception {
        final WorkflowJob project = r.createProject(WorkflowJob.class, "example");
        project.setDefinition(new CpsFlowDefinition(definition, true));
        final WorkflowRun workflowRun = project.scheduleBuild2(0).waitForStart();
        r.waitForCompletion(workflowRun);
        return workflowRun;
    }

    /**
     * Approximates a multiline string in Java.
     *
     * @param lines the lines to concatenate with a newline separator
     * @return the concatenated multiline string
     */
    private static String m(String... lines) {
        return String.join("\n", lines);
    }
}
