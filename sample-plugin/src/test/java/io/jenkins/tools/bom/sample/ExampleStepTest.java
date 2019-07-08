package io.jenkins.tools.bom.sample;

import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition;
import org.jenkinsci.plugins.workflow.job.WorkflowJob;
import org.jenkinsci.plugins.workflow.job.WorkflowRun;
import org.jenkinsci.plugins.workflow.steps.StepConfigTester;
import static org.junit.Assert.*;
import org.junit.ClassRule;
import org.junit.Test;
import org.junit.Rule;
import org.jvnet.hudson.test.BuildWatcher;
import org.jvnet.hudson.test.JenkinsRule;

public class ExampleStepTest {

    @ClassRule public static BuildWatcher buildWatcher = new BuildWatcher();

    @Rule public JenkinsRule r = new JenkinsRule();

    @Test public void smokes() throws Exception {
        WorkflowJob p = r.createProject(WorkflowJob.class);
        p.setDefinition(new CpsFlowDefinition("node {example(x: 'some value')}; echo 'more stuff too'", true));
        WorkflowRun b = r.buildAndAssertSuccess(p);
        r.assertLogContains("Ran on some value!", b);
        r.assertLogContains("more stuff too", b);
        ExampleStep s = new ExampleStep();
        s.x = "sample";
        ExampleStep s2 = new StepConfigTester(r).configRoundTrip(s);
        assertEquals("sample", s2.x);
    }

}
