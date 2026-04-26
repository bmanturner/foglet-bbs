# Login Screen
1. TextInput 'cursor' indicator doesn't behave like a text input cursor should. Should follow the text being typed.
2. No email validation required (at least on forgot password). Need full form validation.
3. The breadcrumbs don't change based on entering Register or Forgot Password screen.
4. The reset email message gets cropped off the screen on smaller terminals, and the reset password flow just ends. There's no way to consume the token and reset the password. What happens when the delivery_mode is no-email?

# Main Menu Screen
1. Navigation and Oneliners should be a box title, not inside the box
2. Oneliners box has strange '|||||||||||||||||||||' appearing along the top border.
3. Command bar says "↑/↓ Select" but up and down arrow don't appear to do anything.
4. The navigation keys should be accent color

# Account Screen
1. Command bar says "Esc Cancel" but pressing Escape does nothing
2. The tab says "PROFILE", but "Profile" also appears at the top of the content (redundant). Same for Preferences (but not SSH Keys)
3. The Profile screen says Enter to submit, but there is no confirmation anything was submitted, and if I exit and re-enter the Account page, the submitted values are gone.
4. On the Preferences tab, there is no way to select any of the options. 
5. On the Preferences tab, Shift+Tab does not return to previous form field.
6. There's no way to delete the current timezone, or replace it with another timezone. Ideally should be able to select a valid timezone somehow instead of having to type it.
7. [Enter] Submit   [Esc] Cancel is redundant under the menu because it's also on the command bar
8. If I select a different field and type anything, the timezone field is selected and the typed character appears there.
9. On SSH Keys tab it's not possible to paste a SSH Pubkey, so it's impossible to test further.

# Sysop Screen
1. I don't like "Press any key to load". Just load it. Only tab button loads it currently, btw (that's not 'any key')
2. Commandbar says 1-6 Jump, but Tabs on other screens don't always have that.
3. Site tab: Unable to edit any of the values
4. Site tab: Subtitles under each field expose internal planning denotions.
5. Site tab: Says [Enter] Submit   [Esc] Cancel but Enter does nothing and Escape does nothing.
6. Boards tab never loads no matter what I press
7. Limits tab never loads no matter what I press
8. System tab never loads no matter what I press
9. Users tab only loads sometimes. 
10. Users tab says "Invalid status transition."
11. Users tab: None of the advertised keys do anything.
12. Invites tab looks fucked up. Table cramps everything together:
│CodeStatusCreatedUsed by                                                                      ││
││A2TGJQGYMI74JITZAAMavailable  2026-04-26                                                      ││
││UITD46JLDWNNOYAXWNKavailable  2026-04-26                                                      ││
│└TSTUISZHQVGOQA7W5RXavailable  2026-04-26
13. Invites tab: no way to select existing invite codes

# Moderation Screen
1. LOG, USERS, BOARDS tabs break the entire interface. Interface extends above the terminal dimensions

# Boards Screen
1. Entire interface is broken. Interface extends above the terminal dimensions
2. Enter button on a category should open/collapse it
3. Selecting a board and hitting enter does not navigate you to the threads page, it just freezes the screen until you press Q

# Globally
1. There are border glyphs to the right of the right-most tab filling up the remainder of the spacing.
2. Respect newlines a bit better in markdown so all lines aren't cramped together (max 1 line whitespace between lines).
3. The editor doesn't wrap text if a line gets too long.
