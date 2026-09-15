/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "DockViewPrivate.h"

@implementation DockView (Wiggle)

- (void) stopWiggle
{
  [_wiggleTimer invalidate];
  DESTROY(_wiggleTimer);
  DESTROY(_wiggleItem);
  _wiggleStartTime = 0.0;
  _wiggleRepeatsUntilAcknowledged = NO;
  [self setNeedsDisplay:YES];
}


- (void) stepWiggle: (NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  if (!_wiggleItem)
    {
      [self stopWiggle];
      return;
    }

  if (_wiggleRepeatsUntilAcknowledged &&
      now - _wiggleStartTime >= DockAttentionWiggleInterval)
    {
      _wiggleStartTime = now;
    }
  else if (!_wiggleRepeatsUntilAcknowledged &&
	   now - _wiggleStartTime >= DockWiggleDuration)
    {
      [self stopWiggle];
      return;
    }

  [self setNeedsDisplay:YES];
}


- (void) startWiggleForItem: (DockItem *)item
{
  if (!item)
    {
      return;
    }

  [_wiggleTimer invalidate];
  DESTROY(_wiggleTimer);
  ASSIGN(_wiggleItem, item);
  _wiggleStartTime = [NSDate timeIntervalSinceReferenceDate];
  _wiggleRepeatsUntilAcknowledged = NO;
  _wiggleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                  target:self
                                                selector:@selector(stepWiggle:)
                                                userInfo:nil
						 repeats:YES];
  _wiggleTimer = RETAIN(_wiggleTimer);
  [self setNeedsDisplay:YES];
}


- (void) startAttentionWiggleForItem: (DockItem *)item
{
  if (!item)
    {
      return;
    }

  [self startWiggleForItem:item];
  _wiggleRepeatsUntilAcknowledged = YES;
}


- (void) acknowledgeWiggleForItem: (DockItem *)item
{
  if (item && item == _wiggleItem && _wiggleRepeatsUntilAcknowledged)
    {
      [self stopWiggle];
    }
}


- (void) stopRecyclerWiggle
{
  [_recyclerWiggleTimer invalidate];
  DESTROY(_recyclerWiggleTimer);
  _recyclerWiggleStartTime = 0.0;
  [self setNeedsDisplay:YES];
}


- (void) stepRecyclerWiggle: (NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  if (!_recyclerWiggleStartTime ||
      now - _recyclerWiggleStartTime >= DockWiggleDuration)
    {
      [self stopRecyclerWiggle];
      return;
    }

  [self setNeedsDisplay:YES];
}


- (void) startRecyclerWiggle
{
  [_recyclerWiggleTimer invalidate];
  DESTROY(_recyclerWiggleTimer);
  _recyclerWiggleStartTime = [NSDate timeIntervalSinceReferenceDate];
  _recyclerWiggleTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                          target:self
                                                        selector:@selector(stepRecyclerWiggle:)
                                                        userInfo:nil
                                                         repeats:YES];
  _recyclerWiggleTimer = RETAIN(_recyclerWiggleTimer);
  [self setNeedsDisplay:YES];
}


@end
