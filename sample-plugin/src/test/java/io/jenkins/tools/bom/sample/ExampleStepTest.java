package io.jenkins.tools.bom.sample;

import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition;
import org.jenkinsci.plugins.workflow.job.WorkflowJob;
import org.jenkinsci.plugins.workflow.job.WorkflowRun;
import org.junit.Rule;
import org.junit.Test;
import org.jvnet.hudson.test.RealJenkinsRule;

public class ExampleStepTest {

    @Rule
    public RealJenkinsRule r = new RealJenkinsRule();

    @Test
    public void smokes() throws Throwable {
        r.then(r -> {
            WorkflowJob p = r.createProject(WorkflowJob.class);
            p.setDefinition(new CpsFlowDefinition("node {example(x: 'some value')}; echo 'more stuff too'", true));
            WorkflowRun b = p.scheduleBuild2(0).waitForStart();
            r.assertBuildStatusSuccess(r.waitForCompletion(b));
            r.assertLogContains("Ran on some value!", b);
            r.assertLogContains("more stuff too", b);
        });
    }
}
