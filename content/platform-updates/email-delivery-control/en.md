## Find the right order

Open the event and **Orders**. Search by order reference or email. Check payment and delivery separately: a paid order does not confirm ticket delivery.

![Email delivery symbols in the E-mail column of the orders list.](/platform-updates-media/email-delivery-orders.png)

*Screenshots show the Czech interface.*

## Read the symbols

| Email symbol | Meaning |
| --- | --- |
| Envelope with a clock | Waiting, preparing or sending. Open the details for the exact state. |
| Envelope with an arrow | Sent, with delivery unconfirmed. The sending provider has accepted the message. |
| One check mark | Delivered to the recipient's mail server. |
| Two check marks | An open or click was recorded. The details distinguish the two. |
| White envelope in a red circle | Delivery needs attention. Open the details for the reason. A number indicates multiple current issues. |
| Plain envelope | This alone does not establish success. Open the details; status may be unavailable. |

**Server delivery does not prove inbox placement.** Automated mail checks can record opens or clicks, so two check marks do not prove the customer read the message. No recorded open does not mean failed delivery. Tracking is disabled for some messages.

A red warning takes precedence over another message's successful delivery. Read the status text too.

## Identify the missing message

Select the symbol in the email column and open email history (**Historie e-mailů**). Order confirmations, payment notices and tickets have separate states. Message details show available attempt and event times.

![Email history separates individual messages and their delivery states.](/platform-updates-media/email-delivery-history.png)

## All email states

This includes individual attempt events and tracking information. Not every state has its own symbol in the orders table.

### Preparation and sending

| State | Meaning and next action |
| --- | --- |
| **Queued** | Wait and refresh the status. |
| **Preparing message** | The system is preparing the content and attachments. Wait. |
| **Sending** | Sending is in progress. A contact change cannot recall this attempt. |
| **Waiting for payment preparation** | Check payment and the remaining balance. |
| **Sending delayed, will retry** | Another attempt is scheduled. Ask an administrator to investigate persistent delays. |
| **Sent. Delivery not yet confirmed.** | The provider accepted the message. Recipient delivery remains unconfirmed. |
| **Accepted by provider** | A history event: the provider accepted the message. It does not establish delivery. |
| **Provider did not accept message** | This attempt was not accepted. Check later attempts and the current message state. |
| **Send outcome unknown, requires reconciliation** | The message may already have been sent. An administrator must verify the outcome before another send. |

### Delivery and problems

| State | Meaning and next action |
| --- | --- |
| **Delivered to recipient mail server** | Confirm the address; ask the customer to check spam and other folders. |
| **Delivery delayed** | Wait. Ask an administrator to investigate persistent delays. |
| **The email could not be delivered** | Confirm the address with the customer and correct it using the steps below. |
| **Recipient reported spam** | Do not repeat sending to the same address. Speak to the customer and an administrator. |
| **Further sending is blocked after a delivery failure or spam report** | Use another confirmed contact or ask an administrator to investigate the block. |
| **Sending failed** | Open the details and give the administrator the recorded cause. |
| **Provider rejected message** | Open the details and ask an administrator to investigate the rejection. |
| **Provider rendering failed** | An administrator must check message preparation. An address change may not help. |
| **Email accepted; a related update needs attention** | The email may already have been sent. An administrator must check follow-up processing. |
| **Complete** | Follow-up processing has finished. Check message events separately for delivery. |
| **Cancelled** | This message will not be sent. Check the current order. |
| **Expired** | This message is no longer eligible for sending. Check the current order and available actions. |
| **Provider feedback is overdue** | Timely feedback is missing. This does not prove failed delivery; ask an administrator to investigate. |

### Opens, clicks and available information

| State | Meaning and next action |
| --- | --- |
| **Open observed** | An open was recorded; this does not prove the customer read the message. |
| **Click observed** | A click was recorded; this does not prove the customer read the message. |
| **Tracking disabled** | Opens and clicks are not tracked. Assess delivery separately. |
| **No open or click observed** | No open or click was recorded. Delivery may still have succeeded. |
| **Email status unavailable** | Refresh the information. Missing status does not establish success or failure. |

Give the administrator the order reference, message type, displayed status and time.

## Correct the address and choose whether to send

Select the red envelope beside the **order status**. The delivery dialog opens. Editing requires permission to edit orders.

![The contact correction dialog offers saving without sending and sending based on the order state.](/platform-updates-media/email-delivery-repair.png)

1. Confirm the correct address and enter it in the contact email field (**Kontaktní e-mail**).
2. Save only (**Pouze uložit**) changes the contact without sending. The original delivery issue remains unresolved.
3. Choose the offered save-and-send tickets (**Uložit a odeslat vstupenky**) or confirmation (**Uložit a odeslat potvrzení**) action. Without an address change, the button offers send tickets or send confirmation.
4. If prompted, select the message under delivery details (**Podrobnosti doručení**).

Unpaid orders offer a confirmation; paid orders offer tickets. Cancelled orders do not offer another send.

Saving an address cannot recall an email already being sent. Do not create a duplicate order to work around a blocked send action.

## Verify the result

Queued for sending confirms the request. Refresh the order and check the saved contact and the relevant message's subsequent status in the history.
