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
            final WorkflowRun run = runPipeline(r, """
                    pipeline {
                      agent none
                      stages {
                        stage('Example') {
                          steps {
                            example(x: 'foobar')
                          }
                        }
                      }
                    }
                    """);

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
}
