//
//  TilesLayout.m
//  TIBCustomerApp
//
//  Created by Vaishali Gupta on 11/3/15.
//  Copyright © 2015 Rupendra. All rights reserved.
//

#import "TilesLayout.h"


@interface TilesLayout ()
@property(nonatomic) CGPoint firstPoint;
@property(nonatomic) CGPoint lastPoint;

@property(nonatomic) NSMutableDictionary* dictIndexPathByPosition;

@property(nonatomic) NSMutableDictionary* dictPositionByIndexPath;

@property(nonatomic, assign) BOOL isPositionsCached;

@property(nonatomic) NSArray* arrPreviousAttributes;
@property(nonatomic) CGRect previousLayoutRect;

@property(nonatomic) NSIndexPath* lastIndexPathValue;
@end


@implementation TilesLayout

- (id)init {
    if((self = [super init]))
        [self initialize];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if((self = [super initWithCoder:aDecoder]))
        [self initialize];
    
    return self;
}

- (void) initialize {
    // defaults
    self.direction = UICollectionViewScrollDirectionHorizontal;
    self.blockPixels = CGSizeMake(100.f, 100.f);
}

- (CGSize)collectionViewContentSize {
    
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    CGSize size;
    
    CGRect contentRect = UIEdgeInsetsInsetRect(self.collectionView.frame, self.collectionView.contentInset);
    if (isVert)
        size= CGSizeMake(CGRectGetWidth(contentRect), (self.lastPoint.y+1) * self.blockPixels.height);
    else
        size= CGSizeMake((self.lastPoint.x+1) * self.blockPixels.width, CGRectGetHeight(contentRect));
    
    return size;
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
    if (!self.delegate) return @[];
    
    // see the comment on these properties
    if(CGRectEqualToRect(rect, self.previousLayoutRect)) {
        return self.arrPreviousAttributes;
    }
    self.previousLayoutRect = rect;
    
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    int unrestrictedDimensionStart = isVert? rect.origin.y / self.blockPixels.height : rect.origin.x / self.blockPixels.width;
    int unrestrictedDimensionLength = (isVert? rect.size.height / self.blockPixels.height : rect.size.width / self.blockPixels.width) + 1;
    int unrestrictedDimensionEnd = unrestrictedDimensionStart + unrestrictedDimensionLength;
    
    [self fillInBlocksToUnrestrictedRow:self.prelayoutEverything? INT_MAX : unrestrictedDimensionEnd];
    
    // find the indexPaths between those rows
    NSMutableSet* attributes = [NSMutableSet set];
    [self traverseTilesBetweenUnrestrictedDimension:unrestrictedDimensionStart and:unrestrictedDimensionEnd iterator:^(CGPoint point) {
        NSIndexPath* indexPath = [self indexPathForPosition:point];
        
        if(indexPath) [attributes addObject:[self layoutAttributesForItemAtIndexPath:indexPath]];
        return YES;
    }];
    
    return (self.arrPreviousAttributes = [attributes allObjects]);
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if([self.delegate respondsToSelector:@selector(collectionView:layout:insetsForTileAtIndexPath:)])
        insets = [[self delegate] collectionView:[self collectionView] layout:self insetsForTileAtIndexPath:indexPath];
    
    
    CGRect frame = [self frameForIndexPath:indexPath];
    UICollectionViewLayoutAttributes* attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
    attributes.frame = UIEdgeInsetsInsetRect(frame, insets);
    return attributes;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return !(CGSizeEqualToSize(newBounds.size, self.collectionView.frame.size));
}

- (void)prepareForCollectionViewUpdates:(NSArray *)updateItems {
    [super prepareForCollectionViewUpdates:updateItems];
    
    for(UICollectionViewUpdateItem* item in updateItems) {
        if(item.updateAction == UICollectionUpdateActionInsert || item.updateAction == UICollectionUpdateActionMove) {
            [self fillInBlocksToIndexPath:item.indexPathAfterUpdate];
        }
    }
}

- (void) invalidateLayout {
    [super invalidateLayout];
    
    _lastPoint = CGPointZero;
    self.firstPoint = CGPointZero;
    self.previousLayoutRect = CGRectZero;
    self.arrPreviousAttributes = nil;
    self.lastIndexPathValue = nil;
    [self clearPositions];
}

- (void) prepareLayout {
    [super prepareLayout];
    
    if (!self.delegate) return;
    
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    CGRect scrollFrame = CGRectMake(self.collectionView.contentOffset.x, self.collectionView.contentOffset.y, self.collectionView.frame.size.width, self.collectionView.frame.size.height);
    
    int unrestrictedRow = 0;
    if (isVert)
        unrestrictedRow = (CGRectGetMaxY(scrollFrame) / [self blockPixels].height)+1;
    else
        unrestrictedRow = (CGRectGetMaxX(scrollFrame) / [self blockPixels].width)+1;
    
    [self fillInBlocksToUnrestrictedRow:self.prelayoutEverything? INT_MAX : unrestrictedRow];
}

- (void) setDirection:(UICollectionViewScrollDirection)direction {
    _direction = direction;
    [self invalidateLayout];
}

- (void) setBlockPixels:(CGSize)size {
    _blockPixels = size;
    [self invalidateLayout];
}


#pragma mark private methods

- (void) fillInBlocksToUnrestrictedRow:(int)endRow {
    
    BOOL vert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    // we'll have our data structure as if we're planning
    // a vertical layout, then when we assign positions to
    // the items we'll invert the axis
    
    NSInteger numSections = [self.collectionView numberOfSections];
    for (NSInteger section=self.lastIndexPathValue.section; section<numSections; section++) {
        NSInteger numRows = [self.collectionView numberOfItemsInSection:section];
        
        for (NSInteger row = (!self.lastIndexPathValue? 0 : self.lastIndexPathValue.row + 1); row<numRows; row++) {
            NSIndexPath* indexPath = [NSIndexPath indexPathForRow:row inSection:section];
            
            if([self placeBlockAtIndex:indexPath]) {
                self.lastIndexPathValue = indexPath;
            }
            
            // only jump out if we've already filled up every space up till the resticted row
            if((vert? self.firstPoint.y : self.firstPoint.x) >= endRow)
                return;
        }
    }
}

- (void) fillInBlocksToIndexPath:(NSIndexPath*)path {
    
    // we'll have our data structure as if we're planning
    // a vertical layout, then when we assign positions to
    // the items we'll invert the axis
    
    NSInteger numSections = [self.collectionView numberOfSections];
    for (NSInteger section=self.lastIndexPathValue.section; section<numSections; section++) {
        NSInteger numRows = [self.collectionView numberOfItemsInSection:section];
        
        for (NSInteger row=(!self.lastIndexPathValue? 0 : self.lastIndexPathValue.row+1); row<numRows; row++) {
            
            // exit when we are past the desired row
            if(section >= path.section && row > path.row) { return; }
            
            NSIndexPath* indexPath = [NSIndexPath indexPathForRow:row inSection:section];
            
            if([self placeBlockAtIndex:indexPath]) { self.lastIndexPathValue = indexPath; }
            
        }
    }
}

- (BOOL) placeBlockAtIndex:(NSIndexPath*)indexPath {
    CGSize blockSize = [self getBlockSizeForItemAtIndexPath:indexPath];
    BOOL vert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    
    return ![self traverseOpenTiles:^(CGPoint blockOrigin) {
        
        //Placing the blocks
        
        BOOL didTraverseAllBlocks = [self traverseTilesForPoint:blockOrigin withSize:blockSize iterator:^(CGPoint point) {
            BOOL spaceAvailable = (BOOL)![self indexPathForPosition:point];
            BOOL inBounds = (vert? point.x : point.y) < [self restrictedDimensionBlockSize];
            BOOL maximumRestrictedBoundSize = (vert? blockOrigin.x : blockOrigin.y) == 0;
            
            if (spaceAvailable && maximumRestrictedBoundSize && !inBounds) {
                //                TIBLog(@"%@: layout is not %@ enough for this %@", [self class], vert? @"wide" : @"tall", NSStringFromCGSize(blockSize));
                return YES;
            }
            
            return (BOOL) (spaceAvailable && inBounds);
        }];
        
        
        if (!didTraverseAllBlocks) { return YES; }
        
        // because we have determined that the space is all
        // available, lets fill it in as taken.
        
        [self setIndexPath:indexPath forPosition:blockOrigin];
        
        [self traverseTilesForPoint:blockOrigin withSize:blockSize iterator:^(CGPoint point) {
            
            
            [self setPosition:point forIndexPath:indexPath];
            
            self.lastPoint = point;
            
            return YES;
        }];
        
        return NO;
    }];
}

// returning no in the callback will
// terminate the iterations early
- (BOOL) traverseTilesBetweenUnrestrictedDimension:(int)begin and:(int)end iterator:(BOOL(^)(CGPoint))block {
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    // the double ;; is deliberate, the unrestricted dimension should iterate indefinitely
    for(int unrestrictedDimension = begin; unrestrictedDimension<end; unrestrictedDimension++) {
        for(int restrictedDimension = 0; restrictedDimension<[self restrictedDimensionBlockSize]; restrictedDimension++) {
            CGPoint point = CGPointMake(isVert? restrictedDimension : unrestrictedDimension, isVert? unrestrictedDimension : restrictedDimension);
            
            if(!block(point)) { return NO; }
        }
    }
    
    return YES;
}

// returning no in the callback will
// terminate the iterations early
- (BOOL) traverseTilesForPoint:(CGPoint)point withSize:(CGSize)size iterator:(BOOL(^)(CGPoint))block {
    for(int col=point.x; col<point.x+size.width; col++) {
        for (int row=point.y; row<point.y+size.height; row++) {
            if(!block(CGPointMake(col, row))) {
                return NO;
            }
        }
    }
    return YES;
}

// returning no in the callback will
// terminate the iterations early
- (BOOL) traverseOpenTiles:(BOOL(^)(CGPoint))block {
    BOOL allTakenBefore = YES;
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    // the double ;; is deliberate, the unrestricted dimension should iterate indefinitely
    for(int unrestrictedDimension = (isVert? self.firstPoint.y : self.firstPoint.x);; unrestrictedDimension++) {
        for(int restrictedDimension = 0; restrictedDimension<[self restrictedDimensionBlockSize]; restrictedDimension++) {
            
            CGPoint point = CGPointMake(isVert? restrictedDimension : unrestrictedDimension, isVert? unrestrictedDimension : restrictedDimension);
            
            if([self indexPathForPosition:point]) { continue; }
            
            if(allTakenBefore) {
                self.firstPoint = point;
                allTakenBefore = NO;
            }
            
            if(!block(point)) {
                return NO;
            }
        }
    }
    
    NSAssert(0, @"Could find no good place for a block!");
    return YES;
}

- (void) clearPositions {
    self.dictIndexPathByPosition = [NSMutableDictionary dictionary];
    self.dictPositionByIndexPath = [NSMutableDictionary dictionary];
}

- (NSIndexPath*)indexPathForPosition:(CGPoint)point {
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    // to avoid creating unbounded nsmutabledictionaries we should
    // have the innerdict be the unrestricted dimension
    
    NSNumber* unrestrictedPoint = @(isVert? point.y : point.x);
    NSNumber* restrictedPoint = @(isVert? point.x : point.y);
    
    return self.dictIndexPathByPosition[restrictedPoint][unrestrictedPoint];
}

- (void) setPosition:(CGPoint)point forIndexPath:(NSIndexPath*)indexPath {
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    // to avoid creating unbounded nsmutabledictionaries we should
    // have the innerdict be the unrestricted dimension
    
    NSNumber* unrestrictedPoint = @(isVert? point.y : point.x);
    NSNumber* restrictedPoint = @(isVert? point.x : point.y);
    
    NSMutableDictionary* innerDict = self.dictIndexPathByPosition[restrictedPoint];
    if (!innerDict)
        self.dictIndexPathByPosition[restrictedPoint] = [NSMutableDictionary dictionary];
    
    self.dictIndexPathByPosition[restrictedPoint][unrestrictedPoint] = indexPath;
}


- (void) setIndexPath:(NSIndexPath*)path forPosition:(CGPoint)point {
    NSMutableDictionary* innerDict = self.dictPositionByIndexPath[@(path.section)];
    if (!innerDict) self.dictPositionByIndexPath[@(path.section)] = [NSMutableDictionary dictionary];
    
    self.dictPositionByIndexPath[@(path.section)][@(path.row)] = [NSValue valueWithCGPoint:point];
}

- (CGPoint) positionForIndexPath:(NSIndexPath*)path {
    
    // if item does not have a position, we will make one!
    if(!self.dictPositionByIndexPath[@(path.section)][@(path.row)])
        [self fillInBlocksToIndexPath:path];
    
    return [self.dictPositionByIndexPath[@(path.section)][@(path.row)] CGPointValue];
}


- (CGRect) frameForIndexPath:(NSIndexPath*)path {
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    CGPoint position = [self positionForIndexPath:path];
    CGSize elementSize = [self getBlockSizeForItemAtIndexPath:path];
    
    CGRect contentRect = UIEdgeInsetsInsetRect(self.collectionView.frame, self.collectionView.contentInset);
    if (isVert) {
        float initialPaddingForContraintedDimension = (CGRectGetWidth(contentRect) - [self restrictedDimensionBlockSize]*self.blockPixels.width)/ 2;
        return CGRectMake(position.x*self.blockPixels.width + initialPaddingForContraintedDimension,
                          position.y*self.blockPixels.height,
                          elementSize.width*self.blockPixels.width,
                          elementSize.height*self.blockPixels.height);
    } else {
        float initialPaddingForContraintedDimension = (CGRectGetHeight(contentRect) - [self restrictedDimensionBlockSize]*self.blockPixels.height)/ 2;
        return CGRectMake(position.x*self.blockPixels.width,
                          position.y*self.blockPixels.height + initialPaddingForContraintedDimension,
                          elementSize.width*self.blockPixels.width,
                          elementSize.height*self.blockPixels.height);
    }
}


//This method is prefixed with get because it may return its value indirectly
- (CGSize)getBlockSizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGSize blockSize = CGSizeMake(1, 1);
    if([self.delegate respondsToSelector:@selector(collectionView:layout:tileSizeAtIndexPath:)])
        blockSize = [[self delegate] collectionView:[self collectionView] layout:self tileSizeAtIndexPath:indexPath];
    return blockSize;
}


// this will return the maximum width or height the quilt
// layout can take, depending on we're growing horizontally
// or vertically

- (int) restrictedDimensionBlockSize {
    BOOL isVert = self.direction == UICollectionViewScrollDirectionHorizontal;
    
    CGRect contentRect = UIEdgeInsetsInsetRect(self.collectionView.frame, self.collectionView.contentInset);
    int size = isVert? CGRectGetWidth(contentRect) / self.blockPixels.width : CGRectGetHeight(contentRect) / self.blockPixels.height;
    
    if(size == 0) {
        static BOOL didShowMessage;
        if(!didShowMessage) {
            //            TIBLog(@"%@: cannot fit block of size: %@ in content rect %@!  Defaulting to 1", [self class], NSStringFromCGSize(self.blockPixels), NSStringFromCGRect(contentRect));
            didShowMessage = YES;
        }
        return 1;
    }
    
    return size;
}

- (void) setFurthestBlockPoint:(CGPoint)point {
    _lastPoint = CGPointMake(MAX(self.lastPoint.x, point.x), MAX(self.lastPoint.y, point.y));
}



@end