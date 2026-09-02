import { assertEquals, assertThrows } from "jsr:@std/assert";
import { canonicalSnsString, SnsVerificationError, trustedSnsUrl } from "./snsVerification.ts";

const topic = "arn:aws:sns:eu-central-1:274371802740:festapp-bank-emails";

Deno.test("SNS canonical notification string uses the AWS field order", () => {
  assertEquals(canonicalSnsString({
    Type: "Notification",
    MessageId: "id",
    TopicArn: topic,
    Subject: "subject",
    Message: "message",
    Timestamp: "2026-09-02T00:00:00Z",
  }), "Message\nmessage\nMessageId\nid\nSubject\nsubject\nTimestamp\n2026-09-02T00:00:00Z\nTopicArn\n" + topic + "\nType\nNotification\n");
});

Deno.test("SNS URLs are pinned to the exact topic region and AWS certificate shape", () => {
  assertEquals(
    trustedSnsUrl("https://sns.eu-central-1.amazonaws.com/SimpleNotificationService-abc123.pem", topic).hostname,
    "sns.eu-central-1.amazonaws.com",
  );
  for (const value of [
    "http://sns.eu-central-1.amazonaws.com/SimpleNotificationService-a.pem",
    "https://sns.eu-central-1.amazonaws.com.evil.example/SimpleNotificationService-a.pem",
    "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-a.pem",
    "https://sns.eu-central-1.amazonaws.com/other.pem",
  ]) assertThrows(() => trustedSnsUrl(value, topic), SnsVerificationError);
});

Deno.test("subscription confirmation is constrained to the exact topic", () => {
  const url = `https://sns.eu-central-1.amazonaws.com/?Action=ConfirmSubscription&TopicArn=${encodeURIComponent(topic)}&Token=token`;
  assertEquals(trustedSnsUrl(url, topic, true).searchParams.get("Token"), "token");
  assertThrows(
    () => trustedSnsUrl("https://sns.eu-central-1.amazonaws.com/?Action=Unsubscribe&Token=x", topic, true),
    SnsVerificationError,
  );
});
