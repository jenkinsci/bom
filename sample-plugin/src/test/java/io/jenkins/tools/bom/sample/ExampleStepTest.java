package io.jenkins.tools.bom.sample;

import static org.awaitility.Awaitility.await;
import static org.junit.Assert.assertEquals;

import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition;
import org.jenkinsci.plugins.workflow.cps.SnippetizerTester;
import org.jenkinsci.plugins.workflow.job.WorkflowJob;
import org.jenkinsci.plugins.workflow.job.WorkflowRun;
import org.jenkinsci.plugins.workflow.steps.StepConfigTester;
import org.jenkinsci.plugins.workflow.support.steps.input.InputAction;
import org.junit.Rule;
import org.junit.Test;
import org.jvnet.hudson.test.JenkinsSessionRule;
import org.jvnet.hudson.test.RealJenkinsRule;

public class ExampleStepTest {

    @Rule
    public RealJenkinsRule r = new RealJenkinsRule();

    @Rule
    public JenkinsSessionRule sessions = new JenkinsSessionRule();

    @Test
    public void smokes() throws Throwable {
        r.then(r -> {
            WorkflowJob p = r.createProject(WorkflowJob.class);
            p.setDefinition(new CpsFlowDefinition(
                    "node {example(x: 'some value')}; input 'wait'; echo 'more stuff too'", true));
            WorkflowRun b = p.scheduleBuild2(0).waitForStart();
            await().until(() -> {
                InputAction ia = b.getAction(InputAction.class);
                return ia != null && ia.isWaitingForInput();
            });
            b.getAction(InputAction.class).getExecutions().get(0).doProceedEmpty();
            r.assertBuildStatusSuccess(r.waitForCompletion(b));
            r.assertLogContains("Ran on some value!", b);
            r.assertLogContains("more stuff too", b);
        });
    }

    @Test
    public void configRoundTrip() throws Throwable {
        sessions.then(j -> {
            ExampleStep s = new ExampleStep();
            s.x = "sample";
            ExampleStep s2 = new StepConfigTester(j).configRoundTrip(s);
            assertEquals("sample", s2.x);
            new SnippetizerTester(j).assertRoundTrip(s2, "example x: 'sample'");
        });
    }
}
