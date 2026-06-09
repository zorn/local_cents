# Expense Attributes

## Problem Statement

What aspects of an expense do we want to track?

How we manage currency settings?

## Decision

The following is a list of attributes we are considering for phase 1 of the project. We don't expect to have all of these right away, so expect the UI to evolve over time.

- Date - The date of the expense. Note, we do not capture the time of day for an expense, just the date.
- Description - A short single-line text description of the expense.
- Cost - The amount of money spent on the expense.
- Tags - A list of tags that the user can apply to an expense for categorization and filtering. Tags are optional and can be added or removed after the fact.
- Notes - A longer multi-line Markdown-friendly field for the user to capture any additional information they want to capture.
- Attachments - A list of files the user can attach to an expense for reference, generally expected to be a photo of a receipt or a PDF of an invoice.

 We will store the cost as a decimal value and render it in the user's chosen currency format (of which the book will have a single chosen currency format).
